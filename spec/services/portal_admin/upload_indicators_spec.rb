require 'rails_helper'

# B02b, indicators: the delay between a bank movement and the deposit of its document, the share "to complete", the share of documents given in time, the share that came by the portal.
RSpec.describe PortalAdmin::UploadIndicators do
  include_context 'with entity'
  include DocumentFiles

  let(:person) { create(:portal_user) }
  let(:staff)  { create(:user) }

  def request_with(due_on:)
    Portal::DocumentRequest.create!(entity_id: entity.id, requested_by: staff, due_on: due_on)
  end

  def line_of(request, movement_on:, state:, sent_on: nil)
    tx = create(:bank_transaction, transaction_date: movement_on)
    line = request.lines.create!(entity_id: entity.id, bank_transaction_id: tx.id, line_date: movement_on, amount: 1, state: state)
    Portal::Upload.create!(entity_id: entity.id, portal_user: person, filename: 'a.pdf', byte_size: 1, sha256: SecureRandom.hex(32), chunk_size: 1, chunk_count: 1, status: 'accepted',
                           received_at: sent_on.in_time_zone("UTC") + 12.hours, request_line_id: line.id, expires_at: 1.day.from_now) if sent_on
    line
  end

  it 'is empty and says so when nothing happened' do
    expect(described_class.call(entity: entity)).to eq(delay_days: nil, to_complete_rate: nil, in_time_rate: nil, portal_share: nil)
  end

  it 'measures the delay, in days, from the movement to the deposit' do
    request = request_with(due_on: Date.new(2026, 4, 30))
    line_of(request, movement_on: Date.new(2026, 3, 1), state: 'provided', sent_on: Date.new(2026, 3, 11))
    line_of(request, movement_on: Date.new(2026, 3, 1), state: 'provided', sent_on: Date.new(2026, 3, 21))

    expect(described_class.call(entity: entity)[:delay_days]).to eq(BigDecimal('15'))
  end

  it 'counts what was given before the date asked, among what was due' do
    request = request_with(due_on: Date.new(2026, 4, 1))
    line_of(request, movement_on: Date.new(2026, 3, 1), state: 'provided', sent_on: Date.new(2026, 3, 30)) # in time
    line_of(request, movement_on: Date.new(2026, 3, 1), state: 'provided', sent_on: Date.new(2026, 4, 5))  # late
    line_of(request, movement_on: Date.new(2026, 3, 1), state: 'open')                                      # not given, and due

    travel_to(Time.zone.local(2026, 4, 10)) { expect(described_class.call(entity: entity)[:in_time_rate]).to eq(BigDecimal('33.3')) }
  end

  it 'gives the share of what the clients sent that is to be completed' do
    4.times { |i| Portal::Upload.create!(entity_id: entity.id, portal_user: person, filename: "f#{i}.pdf", byte_size: 1, sha256: SecureRandom.hex(32), chunk_size: 1, chunk_count: 1,
                                         status: (i.zero? ? 'to_complete' : 'accepted'), expires_at: 1.day.from_now, received_at: Time.current) }

    expect(described_class.call(entity: entity)[:to_complete_rate]).to eq(BigDecimal('25'))
  end

  it 'gives the share of the documents that came by the portal rather than by e-mail' do
    Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('p1')), filename: 'p1.pdf', user: nil, origin: :portal)
    Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('p2')), filename: 'p2.pdf', user: nil, origin: :portal)
    Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('p3')), filename: 'p3.pdf', user: nil, origin: :portal)
    Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('m1')), filename: 'm1.pdf', user: nil, origin: :email)
    Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('u1')), filename: 'u1.pdf', user: staff) # by hand: in neither

    expect(described_class.call(entity: entity)[:portal_share]).to eq(BigDecimal('75'))
  end
end
