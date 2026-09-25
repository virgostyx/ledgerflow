require 'rails_helper'

# Written from the B2Brouter API documentation and one real exchange (importing a UBL of ours in the sandbox); the send
# step and the webhook payloads are taken from the documentation only.
RSpec.describe Peppol::AccessPoint::B2brouter do
  let(:entity) do
    create(:entity, peppol_access_point: :b2brouter, peppol_participant_id: '0208:1031871152',
                    peppol_credentials: { 'api_key' => 'test_key', 'account_id' => '343740', 'webhook_secret' => 'whsec' })
  end
  let(:access_point) { described_class.new(entity) }
  let(:send_args) { { xml: '<Invoice/>', sender: '0208:1031871152', receiver: '0208:0987654321', document_id: 'VTE2026/0001' } }
  let(:base) { Regexp.escape(B2BROUTER_API_URL) }
  let(:import_url) { %r{#{base}/accounts/343740/invoices/import} }
  let(:send_url)   { %r{#{base}/invoices/send_invoice/555} }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def sign(body, t = Time.now.to_i, secret = 'whsec') = "t=#{t},s=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{t}.#{body}")}"

  def webhook(state, notes: nil)
    body = { code: 'issued_invoice.state_change', triggered_at: 1, data: { account_id: 343740, invoice_id: 555, event_id: 1, state: state, notes: notes } }.to_json
    { headers: { 'X-B2Brouter-Signature' => sign(body) }, body: body }
  end

  it_behaves_like 'a Peppol access point' do
    let(:accept_send!) do
      stub_request(:post, import_url).to_return(status: 201, body: { invoice: { id: 555, state: 'new' } }.to_json, headers: json)
      stub_request(:post, send_url).to_return(status: 200, body: { invoice: { id: 555, state: 'sent' } }.to_json, headers: json)
    end
    let(:refused_send_args) do
      stub_request(:post, import_url).to_return(status: 422, body: { error: { message: 'Contact: VAT is invalid' } }.to_json, headers: json)
      send_args
    end
    before { stub_request(:get, %r{#{base}/directory/}).to_return(status: 404, body: '{}', headers: json) }

    let(:delivered_webhook)  { webhook('closed') }
    let(:delivered_message_id) { '555' }
    let(:forged_webhook)     { { headers: { 'X-B2Brouter-Signature' => 't=1,s=forged' }, body: webhook('closed')[:body] } }
  end

  describe '.credential_fields' do
    it 'asks for an API key, an account id and a webhook secret, all required' do
      fields = described_class.credential_fields.index_by { |f| f[:key] }

      expect(fields.keys).to contain_exactly('api_key', 'account_id', 'webhook_secret')
      expect(fields.values).to all(include(required: true))
      expect(fields['account_id']).not_to include(secret: true)
      expect(fields.values_at('api_key', 'webhook_secret')).to all(include(secret: true))
    end
  end

  describe '#send_document' do
    it 'imports the XML as base64 then sends the imported invoice, with the key and API version headers' do
      import = stub_request(:post, import_url).with(
        headers: { 'X-B2B-API-Key' => 'test_key', 'X-B2B-API-Version' => described_class::API_VERSION, 'Content-Type' => 'application/octet-stream' },
        query: { 'send_after_import' => 'false' },
        body: "data:text/xml;name=invoice.xml;base64,#{Base64.strict_encode64('<Invoice/>')}"
      ).to_return(status: 201, body: { invoice: { id: 555 } }.to_json, headers: json)
      sending = stub_request(:post, send_url).with(headers: { 'X-B2B-API-Key' => 'test_key' })
                                             .to_return(status: 200, body: {}.to_json, headers: json)

      expect(access_point.send_document(**send_args)).to eq('555')
      expect(import).to have_been_requested
      expect(sending).to have_been_requested
    end

    it 'gives the message of the API when it refuses the import' do
      stub_request(:post, import_url).to_return(status: 422, body: { error: { message: 'Contact: VAT is invalid' } }.to_json, headers: json)
      expect { access_point.send_document(**send_args) }.to raise_error(Peppol::AccessPoint::Error, /VAT is invalid/)
    end

    it 'gives the message of the API when it refuses the send' do
      stub_request(:post, import_url).to_return(status: 201, body: { invoice: { id: 555 } }.to_json, headers: json)
      stub_request(:post, send_url).to_return(status: 422, body: { error: { message: 'Not on Peppol' } }.to_json, headers: json)
      expect { access_point.send_document(**send_args) }.to raise_error(Peppol::AccessPoint::Error, /Not on Peppol/)
    end

    it 'raises Error on a network failure' do
      stub_request(:post, import_url).to_timeout
      expect { access_point.send_document(**send_args) }.to raise_error(Peppol::AccessPoint::Error)
    end

    it 'raises Error when the API returns no invoice id' do
      stub_request(:post, import_url).to_return(status: 201, body: '{}', headers: json)
      expect { access_point.send_document(**send_args) }.to raise_error(Peppol::AccessPoint::Error, /no invoice id/)
    end

    it 'raises NotConfigured without an API key or account id' do
      entity.peppol_credentials = { 'webhook_secret' => 'x' }
      expect { access_point.send_document(**send_args) }.to raise_error(Peppol::AccessPoint::NotConfigured)
    end
  end

  describe '#registered?' do
    def directory(status, body = {}) = stub_request(:get, %r{#{base}/directory/be/0208:0987654321}).to_return(status: status, body: body.to_json, headers: json)

    it 'is true for a participant found in the directory' do
      directory(200, { name: 'X' })
      expect(access_point.registered?('0208:0987654321')).to be true
    end

    it 'is false when the directory does not know the participant' do
      directory(404, { error: { code: 'resource_missing' } })
      expect(access_point.registered?('0208:0987654321')).to be false
    end

    it 'is unknown (nil) when the directory cannot answer' do
      directory(500)
      expect(access_point.registered?('0208:0987654321')).to be_nil
    end

    it 'is unknown (nil) for a scheme whose country is not known' do
      expect(access_point.registered?('9925:BE0123456789')).to be_nil
    end
  end

  describe '#parse_webhook' do
    def parse(state, **opts) = access_point.parse_webhook(**webhook(state, **opts))

    %w[closed accepted read paid].each do |state|
      it "reads state #{state} as delivered" do
        expect(parse(state).sole).to have_attributes(kind: :delivered, message_id: '555')
      end
    end

    %w[error refused invalid].each do |state|
      it "reads state #{state} as failed, with the notes as the reason" do
        expect(parse(state, notes: 'Receiver said no').sole).to have_attributes(kind: :failed, message_id: '555', error: 'Receiver said no')
      end
    end

    it 'ignores the states that say nothing about delivery' do
      expect(parse('sent')).to eq([])
      expect(parse('new')).to eq([])
    end

    it 'ignores other events' do
      body = { code: 'ledger.state_change', data: {} }.to_json
      expect(access_point.parse_webhook(headers: { 'X-B2Brouter-Signature' => sign(body) }, body: body)).to eq([])
    end

    it 'refuses a signature computed with another secret, a missing header, or a malformed one' do
      body = webhook('closed')[:body]
      [ sign(body, Time.now.to_i, 'other'), nil, 'garbage' ].each do |header|
        expect { access_point.parse_webhook(headers: { 'X-B2Brouter-Signature' => header }, body: body) }
          .to raise_error(Peppol::AccessPoint::InvalidSignature)
      end
    end

    it 'refuses a body changed after signing' do
      w = webhook('closed')
      expect { access_point.parse_webhook(headers: w[:headers], body: w[:body].sub('closed', 'error')) }
        .to raise_error(Peppol::AccessPoint::InvalidSignature)
    end
  end
end
