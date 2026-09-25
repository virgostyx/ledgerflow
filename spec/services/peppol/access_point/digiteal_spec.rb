require 'rails_helper'

# UNVALIDATED: the Digiteal adapter is written from memory of a public API, never checked against its documentation or a
# sandbox. These tests only pin down what this adapter does with the responses they stub.
RSpec.describe Peppol::AccessPoint::Digiteal do
  let(:entity) do
    create(:entity, peppol_access_point: :digiteal, peppol_participant_id: '0208:0123456789',
                    peppol_credentials: { 'api_key' => 'key-123', 'webhook_secret' => 'whsec-456' })
  end
  let(:access_point) { described_class.new(entity) }
  let(:send_args) { { xml: '<Invoice/>', sender: '0208:0123456789', receiver: '0208:0987654321', document_id: 'VTE2026/0001' } }
  let(:endpoint) { %r{#{Regexp.escape(DIGITEAL_API_URL)}/api/invoices} }

  def sign(body, secret = 'whsec-456') = OpenSSL::HMAC.hexdigest('SHA256', secret, body)

  it_behaves_like 'a Peppol access point' do
    let(:accept_send!) do
      stub_request(:post, endpoint).to_return(status: 201, body: { id: 'DIG-1' }.to_json, headers: { 'Content-Type' => 'application/json' })
    end
    let(:refused_send_args) do
      stub_request(:post, endpoint).to_return(status: 422, body: { error: 'Invalid UBL' }.to_json)
      send_args
    end
    let(:delivered_webhook) do
      body = { event: 'INVOICE_DELIVERED', document_id: 'MSG-1', status: 'DELIVERED' }.to_json
      { headers: { 'X-Peppol-Signature' => sign(body) }, body: body }
    end
    let(:forged_webhook) do
      { headers: { 'X-Peppol-Signature' => 'forged' }, body: { event: 'INVOICE_DELIVERED', document_id: 'MSG-1' }.to_json }
    end
  end

  describe '.credential_fields' do
    it 'asks for an API key and a webhook secret, both required and secret' do
      fields = described_class.credential_fields.index_by { |f| f[:key] }

      expect(fields.keys).to contain_exactly('api_key', 'webhook_secret')
      expect(fields.values).to all(include(required: true, secret: true))
    end
  end

  describe '#send_document' do
    it 'posts the XML with the API key of the entity' do
      stub = stub_request(:post, endpoint)
             .with(headers: { 'Authorization' => 'Bearer key-123', 'Content-Type' => 'application/xml' }, body: '<Invoice/>')
             .to_return(status: 201, body: { id: 'DIG-9' }.to_json)

      expect(access_point.send_document(**send_args)).to eq('DIG-9')
      expect(stub).to have_been_requested
    end

    it 'uses the key of each entity, not a global one' do
      other = described_class.new(create(:entity, peppol_access_point: :digiteal, peppol_credentials: { 'api_key' => 'key-other', 'webhook_secret' => 'x' }))
      stub = stub_request(:post, endpoint).with(headers: { 'Authorization' => 'Bearer key-other' }).to_return(status: 201, body: { id: 'DIG-2' }.to_json)

      other.send_document(**send_args)
      expect(stub).to have_been_requested
    end

    it 'raises an Error, with the reason, on a connection failure' do
      stub_request(:post, endpoint).to_timeout
      expect { access_point.send_document(**send_args) }.to raise_error(Peppol::AccessPoint::Error, /Digiteal/)
    end

    it 'raises an Error on an answer that is not JSON' do
      stub_request(:post, endpoint).to_return(status: 201, body: 'oops')
      expect { access_point.send_document(**send_args) }.to raise_error(Peppol::AccessPoint::Error, /Digiteal/)
    end

    it 'raises NotConfigured when the entity has no API key' do
      entity.peppol_credentials = {} # not saved: the model would refuse it
      expect { access_point.send_document(**send_args) }.to raise_error(Peppol::AccessPoint::NotConfigured, /API key/)
    end
  end

  describe '#registered?' do
    it 'is unknown (nil): no directory lookup is implemented for this provider' do
      expect(access_point.registered?('0208:0123456789')).to be_nil
    end
  end

  describe '#parse_webhook' do
    def parse(payload, secret: 'whsec-456')
      body = payload.to_json
      access_point.parse_webhook(headers: { 'X-Peppol-Signature' => sign(body, secret) }, body: body)
    end

    it 'maps a failed delivery' do
      event = parse({ event: 'INVOICE_DELIVERED', document_id: 'MSG-3', status: 'FAILED' }).sole
      expect(event).to have_attributes(kind: :failed, message_id: 'MSG-3')
    end

    it 'maps a received document, with its XML' do
      event = parse({ event: 'INVOICE_RECEIVED', ubl_xml: '<Invoice/>' }).sole
      expect(event).to have_attributes(kind: :received, xml: '<Invoice/>')
    end

    it 'ignores an event it does not know' do
      expect(parse({ event: 'SOMETHING_ELSE' })).to eq([])
    end

    it 'refuses a signature made with another secret' do
      expect { parse({ event: 'INVOICE_DELIVERED', document_id: 'MSG-1' }, secret: 'not-mine') }
        .to raise_error(Peppol::AccessPoint::InvalidSignature)
    end

    it 'refuses everything when the entity has no webhook secret' do
      entity.peppol_credentials = { 'api_key' => 'key-123' }
      expect { parse({ event: 'INVOICE_DELIVERED', document_id: 'MSG-1' }) }.to raise_error(Peppol::AccessPoint::InvalidSignature)
    end
  end
end
