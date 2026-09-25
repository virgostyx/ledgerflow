require 'rails_helper'

RSpec.describe Peppol::AccessPoint::Simulator do
  include ActiveJob::TestHelper

  let(:entity) { create(:entity, peppol_access_point: :simulator, peppol_participant_id: '0208:0123456789') }
  let(:access_point) { described_class.new(entity) }
  let(:xml) { '<Invoice><ID>VTE2026/0001</ID></Invoice>' }
  let(:send_args) { { xml: xml, sender: '0208:0123456789', receiver: '0208:0987654321', document_id: 'VTE2026/0001' } }

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  def sign(body) = OpenSSL::HMAC.hexdigest('SHA256', entity.peppol_webhook_token, body)

  it_behaves_like 'a Peppol access point' do
    let(:accept_send!) { nil }
    let(:refused_send_args) { send_args.merge(xml: '<not closed') }
    let(:delivered_webhook) do
      body = { event: 'delivered', message_id: 'MSG-1' }.to_json
      { headers: { 'X-Simulator-Signature' => sign(body) }, body: body }
    end
    let(:forged_webhook) do
      { headers: { 'X-Simulator-Signature' => 'forged' }, body: { event: 'delivered', message_id: 'MSG-1' }.to_json }
    end
  end

  it 'needs no credentials' do
    expect(described_class.credential_fields).to eq([])
  end

  describe '#send_document' do
    it 'returns a message id of its own' do
      expect(access_point.send_document(**send_args)).to start_with('SIM-')
    end

    it 'gives a different message id each time' do
      expect(access_point.send_document(**send_args)).not_to eq(access_point.send_document(**send_args))
    end

    it 'refuses a receiver that is not a Peppol identifier' do
      expect { access_point.send_document(**send_args.merge(receiver: 'nobody')) }
        .to raise_error(Peppol::AccessPoint::Error, /not a Peppol participant identifier/)
    end

    it 'refuses a receiver that is not registered' do
      expect { access_point.send_document(**send_args.merge(receiver: '9999:ABC-UNREGISTERED')) }
        .to raise_error(Peppol::AccessPoint::Error, /not registered/i)
    end

    it 'has the delivery confirmed by a job, after the send has returned' do
      message_id = access_point.send_document(**send_args)

      expect(Peppol::SimulatorDeliveryJob).to have_been_enqueued.with(message_id, 'delivered', nil)
    end

    it 'has a delivery failure reported by a job when the receiver ends with -FAILED' do
      message_id = access_point.send_document(**send_args.merge(receiver: '9999:ABC-FAILED'))

      expect(Peppol::SimulatorDeliveryJob).to have_been_enqueued.with(message_id, 'failed', a_string_including('simulated'))
    end

    it 'leaves the document queued, with no job, when the receiver ends with -SLOW' do
      access_point.send_document(**send_args.merge(receiver: '9999:ABC-SLOW'))

      expect(Peppol::SimulatorDeliveryJob).not_to have_been_enqueued
    end
  end

  describe '#registered?' do
    it 'is true for a well-formed identifier' do
      expect(access_point.registered?('0208:0123456789')).to be true
    end

    it 'is false for an identifier ending with -UNREGISTERED or a malformed one' do
      expect(access_point.registered?('9999:ABC-UNREGISTERED')).to be false
      expect(access_point.registered?('nobody')).to be false
    end
  end

  describe '#parse_webhook' do
    it 'reads the events it is given, signed with the webhook token of the entity' do
      body = { event: 'failed', message_id: 'MSG-2', error: 'Receiver rejected it' }.to_json
      events = access_point.parse_webhook(headers: { 'X-Simulator-Signature' => sign(body) }, body: body)

      expect(events.sole).to have_attributes(kind: :failed, message_id: 'MSG-2', error: 'Receiver rejected it')
    end

    it 'reads a received document with its receiver and XML' do
      body = { event: 'received', receiver: '0208:0123456789', xml: xml }.to_json
      events = access_point.parse_webhook(headers: { 'X-Simulator-Signature' => sign(body) }, body: body)

      expect(events.sole).to have_attributes(kind: :received, receiver: '0208:0123456789', xml: xml)
    end

    it 'refuses a body that is not JSON, even signed' do
      expect { access_point.parse_webhook(headers: { 'X-Simulator-Signature' => sign('nope') }, body: 'nope') }
        .to raise_error(Peppol::AccessPoint::Error)
    end
  end

  describe '#simulate_incoming' do
    it 'books a sample supplier invoice addressed to the entity, as a received document would be' do
      ActsAsTenant.with_tenant(entity) { create(:fiscal_year, status: :open) }

      result = ActsAsTenant.without_tenant { access_point.simulate_incoming }

      expect(result).to be_success
      expect(result[:invoice]).to have_attributes(invoice_type: 'supplier', status: 'draft', entity_id: entity.id)
    end

    it 'says why nothing was booked' do
      expect(ActsAsTenant.without_tenant { access_point.simulate_incoming }.message).to match(/open fiscal year/)
    end

    it 'needs the entity to have a Peppol identifier' do
      entity.update!(peppol_participant_id: nil)
      expect { access_point.simulate_incoming }.to raise_error(Peppol::AccessPoint::Error, /identifier/)
    end
  end
end
