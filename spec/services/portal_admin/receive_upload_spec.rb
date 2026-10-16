require 'rails_helper'

# B02b, reception on the firm's side: quarantine, type read from the bytes, cleaning of the PDF, conversion of the photos, antivirus, duplicates, then an ordinary document of
# the inbox (F03) that remembers who sent it. Nothing is executed, nothing is read by a model.
RSpec.describe PortalAdmin::ReceiveUpload do
  include DocumentFiles

  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user, full_name: 'Jane Client') }

  def eicar = 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'

  # The upload as it is once the last chunk has come: in quarantine, in chunks.
  def received(bytes, filename: 'doc.pdf', batch: nil, page: nil, pages: nil, **attrs)
    upload = Portal::Upload.create!(entity_id: entity.id, portal_user: person, filename: filename, byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes),
                                    chunk_size: Portal::Upload::CHUNK_SIZE, chunk_count: [ (bytes.bytesize.to_f / Portal::Upload::CHUNK_SIZE).ceil, 1 ].max, status: 'received',
                                    received_at: Time.current, expires_at: 48.hours.from_now, batch_token: batch, page_number: page, page_count: pages, **attrs)
    (0...upload.chunk_count).map { |i| bytes.b.byteslice(i * Portal::Upload::CHUNK_SIZE, Portal::Upload::CHUNK_SIZE) }.each_with_index do |part, i|
      upload.chunks.create!(position: i, byte_size: part.bytesize, sha256: Digest::SHA256.hexdigest(part), content: part)
    end
    upload
  end

  def run(*uploads) = described_class.call(uploads.flatten)

  def document_of(upload) = ActsAsTenant.with_tenant(entity) { Accounting::Document.find(upload.reload.document_id) }

  def image(width, height, format: 'jpeg', extra: [])
    ExternalCommandForSpecs.run(width, height, format, extra)
  end

  # A JPEG whose EXIF says it must be turned a quarter (orientation 6): the photo of a phone held upright.
  def rotated_jpeg
    jpeg = image(40, 20)
    tiff = "II*\x00\x08\x00\x00\x00".b + [ 1 ].pack('v') + [ 0x0112, 3, 1, 6 ].pack('vvVv') + "\x00\x00".b + "\x00\x00\x00\x00".b
    exif = "Exif\x00\x00".b + tiff
    jpeg.byteslice(0, 2) + "\xFF\xE1".b + [ exif.bytesize + 2 ].pack('n') + exif + jpeg.byteslice(2..)
  end

  def dimensions(bytes)
    Open3.capture2('identify', '-format', '%wx%h', '-', stdin_data: bytes, binmode: true).first
  end

  around do |example|
    previous = Rails.configuration.x.document_virus_scan
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  ensure
    Rails.configuration.x.document_virus_scan = previous
  end

  def with_scanner
    path = File.join(@dir, 'scanner.sh')
    File.write(path, "#!/bin/sh\nif grep -q EICAR-STANDARD; then exit 1; fi\nexit 0\n")
    File.chmod(0o755, path)
    Rails.configuration.x.document_virus_scan = { command: [ path ], fail_open: false }
  end

  describe 'a file that is fine' do
    it 'becomes a document of the inbox that remembers who sent it, with what they said and no more' do
      upload = received(sample_pdf('Invoice 1'), filename: 'invoice.pdf', hint_kind: 'expense_report', hint_note: 'lunch with a client')

      run(upload)

      document = document_of(upload)
      expect(upload.reload.status).to eq('accepted')
      expect(document).to be_inbox
      expect(document.origin).to eq('portal')
      expect(document.kind).to eq('other') # the client never decides how it is booked
      expect(document.extracted_data['portal_hint']).to include('kind' => 'expense_report', 'note' => 'lunch with a client')
      expect(document.extracted_data['source']).to include('portal_user' => 'Jane Client')
      expect(document.name).to eq('invoice.pdf')
    end

    it 'purges the chunks once the file is in, and writes the audit trail' do
      upload = received(sample_pdf('Invoice 2'))

      run(upload)

      expect(upload.chunks.reload).to be_empty
      expect(ActsAsTenant.with_tenant(entity) { Accounting::AuditLog.where(action: 'portal_upload_accepted').count }).to eq(1)
    end

    it 'takes a spreadsheet and a CSV as they are' do
      xlsx = received(sample_xlsx, filename: 'costs.xlsx')
      csv = received(sample_csv, filename: 'costs.csv')

      run(xlsx)
      run(csv)

      expect([ xlsx.reload.status, csv.reload.status ]).to eq(%w[accepted accepted])
    end
  end

  describe 'a PDF is cleaned (criterion 5)' do
    let(:evil) do
      <<~PDF.b
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R /OpenAction 4 0 R /Names << /EmbeddedFiles << /Names [(a.exe) 5 0 R] >> >> >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 6 0 R /Resources << /Font << /F1 7 0 R >> >> >> endobj
        4 0 obj << /S /JavaScript /JS (app.alert\\('x'\\)) >> endobj
        5 0 obj << /Type /Filespec /F (a.exe) /EF << /F 8 0 R >> >> endobj
        6 0 obj << /Length 44 >> stream
        BT /F1 12 Tf 20 100 Td (Hello invoice) Tj ET
        endstream endobj
        7 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
        8 0 obj << /Type /EmbeddedFile /Length 5 >> stream
        MZEXE
        endstream endobj
        trailer << /Root 1 0 R /Size 9 >>
        %%EOF
      PDF
    end

    it 'keeps the text and drops the scripts, the actions and the embedded files' do
      upload = received(evil, filename: 'evil.pdf')

      run(upload)

      stored = document_of(upload).file.download
      expect(upload.reload.status).to eq('accepted')
      expect(stored).not_to match(/JavaScript|\/JS|EmbeddedFile|OpenAction|\/Launch/)
      expect(PDF::Reader.new(StringIO.new(stored)).pages.first.text).to include('Hello invoice')
    end

    it 'keeps the fingerprint of what was sent, which is not the one of what is kept' do
      upload = received(evil, filename: 'evil.pdf')

      run(upload)

      expect(document_of(upload).extracted_data['portal_hint']['sent_sha256']).to eq(Digest::SHA256.hexdigest(evil))
    end

    it 'refuses a PDF of more than 100 pages' do
      upload = received(sample_multipage_pdf(*Array.new(101) { |i| "page #{i}" }), filename: 'long.pdf')

      run(upload)

      expect(upload.reload).to have_attributes(status: 'refused', refusal_reason: 'too_many_pages')
    end

    it 'accepts a PDF that asks for a password and says it is to be completed' do
      upload = received(sample_encrypted_pdf, filename: 'locked.pdf')

      run(upload)

      expect(upload.reload.status).to eq('to_complete')
      expect(document_of(upload).extracted_data['unreadable']).to eq('password_protected')
    end

    it 'refuses a PDF that is not one' do
      upload = received("%PDF-1.4\nnot really", filename: 'broken.pdf')

      run(upload)

      expect(upload.reload).to have_attributes(status: 'refused', refusal_reason: 'corrupted')
    end
  end

  describe 'what is refused or neutralised (criterion 5)' do
    it 'refuses the antivirus test file' do
      with_scanner
      upload = received("#{eicar}\n", filename: 'invoice.csv')

      run(upload)

      expect(upload.reload).to have_attributes(status: 'refused', refusal_reason: 'infected')
      expect(Accounting::Document.unscoped.count).to eq(0)
    end

    it 'lets nothing in while the antivirus cannot answer, and tries again later' do
      Rails.configuration.x.document_virus_scan = { command: [ File.join(@dir, 'missing') ], fail_open: false }
      upload = received(sample_pdf('Invoice 9'))

      run(upload)

      expect(upload.reload.status).to eq('received')
      expect(upload.chunks.count).to eq(1)
      with_scanner
      run(upload)
      expect(upload.reload.status).to eq('accepted')
    end

    it 'refuses a file that is not what its name says' do
      upload = received("\x7FELF\x02\x01\x01".b + 'x' * 200, filename: 'invoice.pdf')

      run(upload)

      expect(upload.reload).to have_attributes(status: 'refused', refusal_reason: 'unsupported_type')
    end

    it 'refuses an image of 200 megapixels without opening it' do
      header = ->(type, data) { [ data.bytesize ].pack('N') + type + data + [ Zlib.crc32(type + data) ].pack('N') }
      bomb = "\x89PNG\r\n\x1a\n".b + header.call('IHDR', [ 20_000, 10_000, 8, 2, 0, 0, 0 ].pack('NNCCCCC')) + header.call('IDAT', Zlib::Deflate.deflate("\0".b)) + header.call('IEND', '')
      upload = received(bomb, filename: 'photo.png')

      run(upload)

      expect(upload.reload).to have_attributes(status: 'refused', refusal_reason: 'image_too_large')
    end

    it 'refuses an archive' do
      zip = Zip::OutputStream.write_buffer { |z| z.put_next_entry('a.txt'); z.write('hi') }.string
      upload = received(zip, filename: 'a.zip')

      run(upload)

      expect(upload.reload.refusal_reason).to eq('unsupported_type')
    end

    it 'says it is a duplicate when the same file comes twice, and makes one document' do
      pdf = sample_pdf('Invoice 3')
      first = received(pdf)
      second = received(pdf)

      run(first)
      run(second)

      expect(second.reload).to have_attributes(status: 'refused', refusal_reason: 'duplicate')
      expect(Accounting::Document.unscoped.where(entity_id: entity.id).count).to eq(1)
    end
  end

  describe 'photos (criterion 4)' do
    it 'turns a photo upright from its EXIF orientation, and reduces it' do
      upload = received(rotated_jpeg, filename: 'photo.jpg')

      run(upload)

      expect(dimensions(document_of(upload).file.download)).to eq('20x40')
    end

    it 'reduces a very large photo to 2000 pixels' do
      upload = received(image(3000, 1500), filename: 'big.jpg')

      run(upload)

      expect(dimensions(document_of(upload).file.download)).to eq('2000x1000')
    end

    it 'converts a HEIC photo to JPEG' do
      upload = received(image(64, 48, format: 'heic'), filename: 'IMG_0001.HEIC')

      run(upload)

      document = document_of(upload)
      expect(document.content_type).to eq('image/jpeg')
      expect(document.file.download).to start_with("\xFF\xD8\xFF".b)
    end

    it 'makes one PDF of several pages, in the order chosen' do
      red = image(80, 40, extra: %w[-fill red -draw rectangle\ 0,0,79,39])
      pages = [ received(image(30, 60), filename: 'p2.jpg', batch: 'b1', page: 2, pages: 3),
                received(red, filename: 'p1.jpg', batch: 'b1', page: 1, pages: 3),
                received(image(50, 50), filename: 'p3.jpg', batch: 'b1', page: 3, pages: 3) ]

      run(pages.sort_by(&:page_number))

      document = document_of(pages.first)
      expect(pages.map { |p| p.reload.status }).to all(eq('accepted'))
      expect(pages.map { |p| p.document_id }.uniq.size).to eq(1)
      expect(document.content_type).to eq('application/pdf')
      expect(PDF::Reader.new(StringIO.new(document.file.download)).page_count).to eq(3)
    end

    it 'refuses a page that is not a photo' do
      pages = [ received(image(30, 60), filename: 'p1.jpg', batch: 'b2', page: 1, pages: 2), received(sample_pdf('x'), filename: 'p2.pdf', batch: 'b2', page: 2, pages: 2) ]

      run(pages)

      expect(pages.map { |p| p.reload.refusal_reason }).to all(eq('unsupported_type'))
    end
  end
end
