require "rails_helper"

# F06 step 6: the webhook of B2Brouter for a received invoice, end to end through the controller: the token designates the entity (the payload
# names no receiver), the document is recorded at once, 200 is answered.
RSpec.describe "Peppol::Webhooks, a received invoice from B2Brouter", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_suspense_account"
  include ActiveJob::TestHelper

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  before { entity.update!(peppol_access_point: :b2brouter, peppol_participant_id: "0208:1031871152", peppol_credentials: { "api_key" => "test_key", "account_id" => "343740", "webhook_secret" => "whsec" }) }

  def body(invoice_id: 85_373, account_id: 343_740) = { code: "received_invoice.created", triggered_at: Time.now.to_i, data: { invoice_id: invoice_id, account_id: account_id, state: "new" } }.to_json
  def signed(payload, t = Time.now.to_i) = "t=#{t},s=#{OpenSSL::HMAC.hexdigest('SHA256', 'whsec', "#{t}.#{payload}")}"
  def deliver(payload, token: entity.peppol_webhook_token, signature: signed(payload))
    post "/peppol/webhooks/#{token}", params: payload, headers: { "Content-Type" => "application/json", "X-B2Brouter-Signature" => signature }
  end

  it "records the announced document in the entity of the token, answers 200, and has the document fetched" do
    deliver(body)

    expect(response).to have_http_status(:ok)
    expect(Accounting::PeppolMessage.inbound.sole).to have_attributes(entity_id: entity.id, remote_id: "85373", status: "received")
    expect(Peppol::FetchReceivedJob).to have_been_enqueued
  end

  it "records it once when B2Brouter sends it twice" do
    2.times { deliver(body) }

    expect(Accounting::PeppolMessage.inbound.count).to eq(1)
  end

  it "records nothing for another account than the entity's" do
    deliver(body(account_id: 999))

    expect(response).to have_http_status(:ok)
    expect(Accounting::PeppolMessage.count).to eq(0)
  end

  it "refuses a bad signature and an unknown token, recording nothing" do
    deliver(body, signature: "t=1,s=forged")
    expect(response).to have_http_status(:unauthorized)

    deliver(body, token: "unknown")
    expect(response).to have_http_status(:not_found)
    expect(Accounting::PeppolMessage.count).to eq(0)
  end

  it "does not answer 200 when the announcement itself cannot be recorded: B2Brouter sends it again" do
    allow(Peppol::ReceiveMessage).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "the database is down")

    expect { deliver(body) }.to raise_error(ActiveRecord::StatementInvalid)
  end
end
