require "rails_helper"

RSpec.describe Accounting::UploadDocument do
  include_context "with entity"

  let(:user) { create(:user) }

  def upload(content, filename, **options)
    described_class.call(io: StringIO.new(content), filename: filename, user: user, **options)
  end

  def failure_reason(result) = result[:reason]

  describe "what is accepted (the type is read from the content, not the extension)" do
    {
      "a PDF"   => -> { [ sample_pdf, "invoice.pdf", "application/pdf" ] },
      "a PNG"   => -> { [ sample_png, "scan.png", "image/png" ] },
      "a JPEG"  => -> { [ sample_jpeg, "photo.jpg", "image/jpeg" ] },
      "a TIFF"  => -> { [ sample_tiff, "scan.tif", "image/tiff" ] },
      "an XML (UBL) invoice" => -> { [ sample_ubl, "invoice.xml", "application/xml" ] },
      "a CSV"   => -> { [ sample_csv, "export.csv", "text/csv" ] },
      "an XLSX" => -> { [ sample_xlsx, "book.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ] }
    }.each do |label, sample|
      it "accepts #{label}" do
        content, filename, type = instance_exec(&sample)

        result = upload(content, filename)

        expect(result).to be_success
        expect(result[:document].content_type).to eq(type)
      end
    end

    it "accepts a CODA bank statement, told from the header record, whatever its extension and encoding" do
      %w[simple accents_cp850 accents_latin1].each do |name|
        result = upload(File.binread(Rails.root.join("spec/fixtures/files/coda/#{name}.cod")), "#{name}.txt")

        expect(result).to be_success
        expect(result[:document].content_type).to eq("text/x-coda")
      end
    end

    it "does not take for a CODA file a text that merely starts with zeros" do
      expect(failure_reason(upload("0000 this is only text\r\n", "notes.txt"))).to eq(:unsupported_type)
    end

    it "keeps the real type when the extension lies (a PNG called .pdf)" do
      result = upload(sample_png, "invoice.pdf")

      expect(result).to be_success
      expect(result[:document].content_type).to eq("image/png")
      expect(result[:document].name).to eq("invoice.pdf")
    end
  end

  describe "what is stored" do
    let(:content) { sample_pdf("stored") }
    let(:document) { upload(content, "Facture été 2026 (n°1).pdf", kind: :purchase_invoice)[:document] }

    it "records the name as given, the checksum, the size, who and how" do
      expect(document).to have_attributes(name: "Facture été 2026 (n°1).pdf", sha256: Digest::SHA256.hexdigest(content),
                                          byte_size: content.bytesize, uploaded_by: user, kind: "purchase_invoice", origin: "manual_upload")
      expect(document).to be_inbox
      expect(document.retention_until).to eq(Date.current + 10.years)
    end

    it "stores the bytes untouched, under a file name safe for storage" do
      expect(document.file.download).to eq(content)
      expect(document.file.filename.to_s).not_to match(%r{[^\w.\- ()]})
    end

    it "can come from another origin (e-mail, Peppol...)" do
      expect(upload(sample_pdf("mail"), "m.pdf", origin: :email)[:document]).to be_email
    end
  end

  describe "what is refused" do
    it "an empty file" do
      result = upload("", "empty.pdf")

      expect(result).to be_failure
      expect(failure_reason(result)).to eq(:empty)
    end

    it "a file over the size limit" do
      stub_const("#{described_class}::MAX_BYTES", 100)

      result = upload(sample_pdf, "big.pdf")

      expect(failure_reason(result)).to eq(:too_large)
    end

    it "an executable renamed .pdf" do
      result = upload(sample_exe, "invoice.pdf")

      expect(failure_reason(result)).to eq(:unsupported_type)
      expect(Accounting::Document.count).to eq(0)
    end

    it "a script renamed .csv" do
      expect(failure_reason(upload("#!/bin/sh\nrm -rf /\n\x00".b, "data.csv"))).to eq(:unsupported_type)
    end

    it "an unknown archive" do
      zip = Accounting::Zipper.build([ [ "a.txt", "hello" ] ])

      expect(failure_reason(upload(zip, "files.zip"))).to eq(:unsupported_type)
    end

    it "a text file that is not a CSV by name" do
      expect(failure_reason(upload("just text", "notes.txt"))).to eq(:unsupported_type)
    end

    it "a corrupted PDF" do
      expect(failure_reason(upload("%PDF-1.4\nthis is not a pdf at all", "broken.pdf"))).to eq(:corrupted)
    end

    it "a truncated PNG" do
      expect(failure_reason(upload(sample_png.byteslice(0, 40), "cut.png"))).to eq(:corrupted)
    end

    it "a truncated JPEG" do
      expect(failure_reason(upload(sample_jpeg.byteslice(0, 60), "cut.jpg"))).to eq(:corrupted)
    end

    it "an XML that is not well formed" do
      expect(failure_reason(upload("<Invoice><ID>1</Invoice>", "bad.xml"))).to eq(:corrupted)
    end

    it "an XLSX that is a broken archive" do
      expect(failure_reason(upload("PK\x03\x04garbage".b, "bad.xlsx"))).to eq(:unsupported_type)
    end

    it "an XML with external entities (nothing is ever resolved, the file is refused)" do
      xxe = %(<?xml version="1.0"?><!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><Invoice>&e;</Invoice>)

      result = upload(xxe, "xxe.xml")

      expect(result).to be_failure
      expect(failure_reason(result)).to eq(:unsafe_xml)
      expect(Accounting::Document.count).to eq(0)
    end

    it "gives a message a person can read" do
      result = upload("", "empty.pdf")

      expect(result.message).to match(/empty/i)
    end
  end

  describe "a PDF that asks for a password" do
    it "is kept, and marked unreadable so that nothing is extracted from it" do
      result = upload(sample_encrypted_pdf, "locked.pdf")

      expect(result).to be_success
      expect(result[:document].extracted_data).to include("unreadable" => "password_protected")
    end
  end

  describe "reading it afterwards" do
    def extraction_status(result) = result[:document].extracted_data.dig("extraction", "status")

    it "marks a PDF, a picture or an XML as pending, and queues the reading" do
      [ [ sample_pdf("p"), "a.pdf" ], [ sample_png, "a.png" ], [ sample_ubl, "a.xml" ] ].each do |content, name|
        result = nil
        expect { result = upload(content, name) }.to have_enqueued_job(Accounting::ExtractDocumentJob).with(a_kind_of(Integer), entity.id)
        expect(extraction_status(result)).to eq("pending")
      end
    end

    it "has nothing to read in a spreadsheet or a CSV, and queues nothing" do
      expect { upload(sample_csv, "a.csv") }.not_to have_enqueued_job(Accounting::ExtractDocumentJob)
      expect(extraction_status(upload(sample_xlsx, "a.xlsx"))).to eq("not_applicable")
    end

    it "does not queue a password-protected PDF, which is marked unreadable" do
      result = nil
      expect { result = upload(sample_encrypted_pdf, "l.pdf") }.not_to have_enqueued_job(Accounting::ExtractDocumentJob)
      expect(extraction_status(result)).to eq("unreadable")
    end

    it "queues nothing for a refused file" do
      expect { upload(sample_exe, "x.pdf") }.not_to have_enqueued_job(Accounting::ExtractDocumentJob)
    end
  end

  describe "the antivirus" do
    around do |example|
      previous = Rails.configuration.x.document_virus_scan
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    ensure
      Rails.configuration.x.document_virus_scan = previous
    end

    def scanner(exit_otherwise: 0)
      path = File.join(@dir, "scan.sh")
      File.write(path, "#!/bin/sh\nif grep -q EICAR-STANDARD; then exit 1; fi\nexit #{exit_otherwise}\n")
      File.chmod(0o755, path)
      Rails.configuration.x.document_virus_scan = { command: [ path ], fail_open: false }
    end

    it "lets a clean file in when a scanner is configured" do
      scanner

      expect(upload(sample_pdf("clean"), "clean.pdf")).to be_success
    end

    it "refuses an infected file, whatever it claims to be, and keeps nothing of it" do
      scanner
      infected = sample_pdf("looks fine") + "\n%" + 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' + "\n" # a valid PDF carrying the test string as a comment

      result = upload(infected, "invoice.pdf")

      expect(failure_reason(result)).to eq(:infected)
      expect(result.message).to match(/virus/i)
      expect(Accounting::Document.count).to eq(0)
      expect(Accounting::AuditLog.where(action: "document_upload")).to be_empty
    end

    it "refuses everything while the scanner is down, rather than let unchecked files in" do
      scanner(exit_otherwise: 2)

      result = upload(sample_pdf("unchecked"), "u.pdf")

      expect(failure_reason(result)).to eq(:scan_unavailable)
      expect(Accounting::Document.count).to eq(0)
    end

    it "does not scan what it already refuses for another reason" do
      scanner(exit_otherwise: 2)

      expect(failure_reason(upload(sample_exe, "x.pdf"))).to eq(:unsupported_type)
    end
  end

  describe "duplicates" do
    it "refuses the same content twice, pointing to the first document" do
      first = upload(sample_pdf("dup"), "first.pdf")[:document]

      result = upload(sample_pdf("dup"), "second.pdf")

      expect(result).to be_failure
      expect(failure_reason(result)).to eq(:duplicate)
      expect(result[:existing]).to eq(first)
      expect(Accounting::Document.count).to eq(1)
      expect(result.message).to include("first.pdf")
    end

    it "does not mistake another entity's document for a duplicate" do
      other = create(:entity)
      ActsAsTenant.with_tenant(other) { upload(sample_pdf("shared"), "theirs.pdf") }

      expect(upload(sample_pdf("shared"), "mine.pdf")).to be_success
    end
  end

  describe "audit" do
    it "records the upload without keeping any content" do
      document = upload(sample_pdf("audited"), "a.pdf")[:document]

      row = Accounting::AuditLog.where(action: "document_upload", auditable_id: document.id).sole
      expect(row.user_id).to eq(user.id)
      expect(row.payload).to include("name" => "a.pdf", "sha256" => document.sha256)
      expect(row.payload.to_s).not_to include("audited")
    end

    it "records nothing for a refused file" do
      expect { upload("", "empty.pdf") }.not_to change(Accounting::AuditLog, :count)
    end
  end
end
