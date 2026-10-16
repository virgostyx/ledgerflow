require 'rails_helper'

# B02b: every minute, what is in quarantine is taken in: a file alone, a batch of photos only once every page is there.
RSpec.describe PortalAdmin::ReceiveUploads do
  include DocumentFiles

  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user) }

  def received(bytes, filename: 'doc.pdf', **attrs)
    upload = Portal::Upload.create!(entity_id: entity.id, portal_user: person, filename: filename, byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes), chunk_size: Portal::Upload::CHUNK_SIZE,
                                    chunk_count: 1, status: 'received', received_at: Time.current, expires_at: 48.hours.from_now, **attrs)
    upload.chunks.create!(position: 0, byte_size: bytes.bytesize, sha256: upload.sha256, content: bytes)
    upload
  end

  it 'takes in every upload that is received' do
    a = received(sample_pdf('A'))
    b = received(sample_pdf('B'))

    described_class.call

    expect([ a, b ].map { |u| u.reload.status }).to eq(%w[accepted accepted])
  end

  it 'leaves alone what is still being sent' do
    upload = Portal::Upload.create!(entity_id: entity.id, portal_user: person, filename: 'x.pdf', byte_size: 5, sha256: 'a' * 64, chunk_size: 1_048_576, chunk_count: 1, expires_at: 1.day.from_now)

    described_class.call

    expect(upload.reload.status).to eq('receiving')
  end

  it 'waits for the last page of a batch, then makes the one document' do
    first = received(sample_jpeg, filename: 'p1.jpg', batch_token: 'b', page_number: 1, page_count: 2)

    described_class.call
    expect(first.reload.status).to eq('received')

    second = received(sample_jpeg + 'x'.b, filename: 'p2.jpg', batch_token: 'b', page_number: 2, page_count: 2)
    described_class.call

    expect([ first, second ].map { |u| u.reload.status }).to eq(%w[accepted accepted])
    expect([ first, second ].map(&:document_id).uniq.size).to eq(1)
  end

  it 'does not take in the uploads of a company that turned the feature off' do
    entity.update!(features: { 'b02b' => false })
    upload = received(sample_pdf('C'))

    described_class.call

    expect(upload.reload.status).to eq('received')
  end
end
