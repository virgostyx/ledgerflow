require "rails_helper"

# F06 step 6: reception through B2Brouter, from its documentation (webhook "received_invoice.created": invoice_id, account_id, state, no XML; list
# GET /accounts/{id}/invoices?type=ReceivedInvoice; document GET /invoices/{id}/as/xml.ubl.invoice.bis3) and from what was checked on the real
# sandbox (the list answers; the UBL route answers application/xml). NOT checked with a real incoming document: the sandbox does not simulate
# inbound documents ("Not yet simulated: receiving inbound documents").
RSpec.describe "Reception through B2Brouter" do
  include_context "with_open_fiscal_year"
  include_context "with_suspense_account"
  include ActiveJob::TestHelper

  let(:base) { Regexp.escape(B2BROUTER_API_URL) }
  let(:json) { { "Content-Type" => "application/json" } }
  let(:access_point) { Peppol::AccessPoint::B2brouter.new(entity) }
  let!(:purchase_journal) { create(:journal, :purchase) }
  # updated, not created in a `let(:entity)`: the context's around hook would then create it before the transaction of the example starts
  before { entity.update!(peppol_access_point: :b2brouter, peppol_participant_id: "0208:1031871152", peppol_credentials: { "api_key" => "test_key", "account_id" => "343740", "webhook_secret" => "whsec" }) }
  let(:ubl) { PeppolUbl.invoice(number: "SUP-B2B-1", lines: [ [ 100, "S", 21 ] ]) }

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  def sign(body, t = Time.now.to_i) = "t=#{t},s=#{OpenSSL::HMAC.hexdigest('SHA256', 'whsec', "#{t}.#{body}")}"
  def announce(invoice_id: 85_373, account_id: 343_740, code: "received_invoice.created")
    body = { code: code, triggered_at: Time.now.to_i, data: { invoice_id: invoice_id, account_id: account_id, state: "new" } }.to_json
    { headers: { "X-B2Brouter-Signature" => sign(body) }, body: body }
  end
  def messages = Accounting::PeppolMessage.inbound

  describe "the webhook" do
    it "makes a received event of the identifiers it gives, with a stable message id" do
      event = access_point.parse_webhook(**announce).sole

      expect(event).to have_attributes(kind: :received, message_id: "b2brouter-85373", remote_id: "85373", xml: nil)
      expect(event.raw).to include("received_invoice.created")
    end

    it "is not ours when it is about another account, or names no invoice" do
      expect(access_point.parse_webhook(**announce(account_id: 999))).to eq([])
      expect(access_point.parse_webhook(**announce(invoice_id: nil))).to eq([])
    end

    it "ignores the state changes of a received invoice: this application does not manage them" do
      expect(access_point.parse_webhook(**announce(code: "received_invoice.state_change"))).to eq([])
    end

    it "is refused with a wrong or an old signature, as for the other events" do
      forged = announce.merge(headers: { "X-B2Brouter-Signature" => "t=1,s=forged" })
      stale = announce
      stale[:headers] = { "X-B2Brouter-Signature" => sign(stale[:body], 10.minutes.ago.to_i) }

      [ forged, stale ].each { |w| expect { access_point.parse_webhook(**w) }.to raise_error(Peppol::AccessPoint::InvalidSignature) }
    end
  end

  describe "fetching the document" do
    it "reads the UBL BIS 3 of the invoice, with the key of the entity" do
      stub = stub_request(:get, %r{#{base}/invoices/85373/as/xml.ubl.invoice.bis3}).with(headers: { "X-B2B-API-Key" => "test_key" })
             .to_return(status: 200, body: ubl, headers: { "Content-Type" => "application/xml" })

      expect(access_point.fetch_received("85373")).to eq(ubl)
      expect(stub).to have_been_requested
    end

    it "tells a technical error from a refusal" do
      stub_request(:get, %r{/invoices/1/as/}).to_return(status: 503, body: "{}")
      expect { access_point.fetch_received("1") }.to raise_error(Peppol::AccessPoint::TemporaryError)

      stub_request(:get, %r{/invoices/2/as/}).to_timeout
      expect { access_point.fetch_received("2") }.to raise_error(Peppol::AccessPoint::TemporaryError)

      stub_request(:get, %r{/invoices/3/as/}).to_return(status: 404, body: "{}")
      expect { access_point.fetch_received("3") }.to raise_error(Peppol::AccessPoint::Error) { |e| expect(e).not_to be_a(Peppol::AccessPoint::TemporaryError) }
    end

    it "does not call the API with something that is not an identifier" do
      expect { access_point.fetch_received("../accounts") }.to raise_error(Peppol::AccessPoint::Error)
    end
  end

  describe "listing what came in" do
    def page(ids) = { invoices: ids.map { |i| { id: i, type: "ReceivedInvoice", number: "N#{i}", date: "2026-10-01", state: "new" } }, meta: { total_count: ids.size, offset: 0, limit: 100 } }.to_json

    it "lists the received invoices from a date on, with their message ids" do
      stub = stub_request(:get, %r{#{base}/accounts/343740/invoices}).with(query: hash_including("type" => "ReceivedInvoice", "date_from" => "2026-09-01", "limit" => "100", "offset" => "0"))
             .to_return(status: 200, body: page([ 11, 12 ]), headers: json)

      expect(access_point.list_received(since: Date.new(2026, 9, 1))).to eq([ { message_id: "b2brouter-11", remote_id: "11", number: "N11", date: "2026-10-01" },
                                                                             { message_id: "b2brouter-12", remote_id: "12", number: "N12", date: "2026-10-01" } ])
      expect(stub).to have_been_requested
    end

    it "reads all the pages" do
      stub_request(:get, %r{/accounts/343740/invoices}).with(query: hash_including("offset" => "0")).to_return(status: 200, body: page((1..100).to_a), headers: json)
      stub_request(:get, %r{/accounts/343740/invoices}).with(query: hash_including("offset" => "100")).to_return(status: 200, body: page([ 101, 102 ]), headers: json)

      expect(access_point.list_received.size).to eq(102)
    end

    it "lists nothing when nothing came in" do
      stub_request(:get, %r{/accounts/343740/invoices}).to_return(status: 200, body: page([]), headers: json)

      expect(access_point.list_received).to eq([])
    end
  end

  describe "from the announcement to the draft" do
    def receive_announcement = ActsAsTenant.without_tenant { Peppol::AccessPoint.for(entity).parse_webhook(**announce).each { |e| Peppol::HandleEvent.call(event: e, entity: entity) } }
    def fetch_job(message, attempt = 1) = Peppol::FetchReceivedJob.perform_now(message.id, entity.id, attempt)

    it "records the announcement at once, without the XML, and has the document fetched by a job" do
      receive_announcement

      message = messages.sole
      expect(message).to have_attributes(message_id: "b2brouter-85373", remote_id: "85373", status: "received", xml: nil)
      expect(Peppol::FetchReceivedJob).to have_been_enqueued.with(message.id, entity.id)
    end

    it "records an announcement once, however many times the Access Point sends it" do
      2.times { receive_announcement }

      expect(messages.count).to eq(1)
      expect(Peppol::FetchReceivedJob).to have_been_enqueued.once
    end

    it "drafts the invoice once the document is fetched" do
      stub_request(:get, %r{/invoices/85373/as/xml.ubl.invoice.bis3}).to_return(status: 200, body: ubl, headers: { "Content-Type" => "application/xml" })
      receive_announcement

      fetch_job(messages.sole)

      expect(messages.sole.reload).to have_attributes(status: "processed", document_type: "invoice", sender_id: "0208:0123456749", problems: [])
      expect(messages.sole.xml).to include("SUP-B2B-1")
      expect(messages.sole.invoice).to have_attributes(supplier_reference: "SUP-B2B-1", status: "draft")
    end

    it "tries again after a technical error, 1 minute, 5 minutes, 30 minutes, then waits for review: never lost" do
      stub_request(:get, %r{/invoices/85373/as/}).to_return(status: 503, body: "{}")
      receive_announcement
      message = messages.sole
      clear_enqueued_jobs

      [ 1.minute, 5.minutes, 30.minutes ].each_with_index do |wait, i|
        fetch_job(message, i + 1)
        expect(message.reload).to have_attributes(status: "received")
        expect(Peppol::FetchReceivedJob).to have_been_enqueued.with(message.id, entity.id, i + 2).at(be_within(5.seconds).of(wait.from_now))
        clear_enqueued_jobs
      end

      fetch_job(message, 4)
      expect(message.reload).to have_attributes(status: "needs_review")
      expect(message.problems.join).to include("could not be fetched")
      expect(Peppol::FetchReceivedJob).not_to have_been_enqueued
    end

    it "waits for review at once when the document does not exist, saying why" do
      stub_request(:get, %r{/invoices/85373/as/}).to_return(status: 404, body: "{}")
      receive_announcement

      fetch_job(messages.sole)

      expect(messages.sole.reload).to have_attributes(status: "needs_review")
      expect(messages.sole.problems.join).to include("85373")
    end

    it "is fetched by 'Work on it again' when the job never got through" do
      receive_announcement
      stub_request(:get, %r{/invoices/85373/as/}).to_return(status: 200, body: ubl, headers: { "Content-Type" => "application/xml" })

      Peppol::MessageActions.reprocess(message: messages.sole, user: create(:user, role: :accountant))

      expect(messages.sole.reload).to have_attributes(status: "processed")
    end

    it "says that the Access Point cannot be reached, and leaves the message as it is" do
      receive_announcement
      stub_request(:get, %r{/invoices/85373/as/}).to_return(status: 503, body: "{}")

      Peppol::MessageActions.reprocess(message: messages.sole, user: create(:user, role: :accountant))

      expect(messages.sole.reload).to have_attributes(status: "received")
      expect(messages.sole.problems.join).to include("cannot be reached")
    end
  end

  describe Peppol::PullReceivedJob do
    def listed(*ids) = stub_request(:get, %r{/accounts/343740/invoices}).to_return(status: 200, headers: json, body: { invoices: ids.map { |i| { id: i, number: "N#{i}", date: "2026-10-01" } }, meta: { total_count: ids.size, offset: 0, limit: 100 } }.to_json)

    before { entity }

    it "records the documents it does not know, as a webhook would have, and has them fetched" do
      listed(21, 22)

      expect(described_class.perform_now).to eq(2)

      expect(messages.pluck(:message_id)).to match_array(%w[b2brouter-21 b2brouter-22])
      expect(messages.pluck(:status).uniq).to eq([ "received" ])
      expect(Peppol::FetchReceivedJob).to have_been_enqueued.twice
    end

    it "leaves alone what a webhook already recorded" do
      listed(21)
      ActsAsTenant.with_tenant(entity) { Peppol::ReceiveMessage.call(event: Peppol::Event.new(kind: :received, message_id: "b2brouter-21", remote_id: "21")) }
      clear_enqueued_jobs

      expect(described_class.perform_now).to eq(0)
      expect(Peppol::FetchReceivedJob).not_to have_been_enqueued
    end

    it "asks for the last thirty days only" do
      stub = stub_request(:get, %r{/accounts/343740/invoices}).with(query: hash_including("date_from" => 30.days.ago.to_date.iso8601)).to_return(status: 200, headers: json, body: { invoices: [], meta: {} }.to_json)

      described_class.perform_now

      expect(stub).to have_been_requested
    end

    it "does not touch an entity whose Access Point does not make us fetch (the simulator), nor one without an Access Point" do
      create(:entity, peppol_access_point: :simulator, peppol_participant_id: "0208:0222222222")
      create(:entity)
      listed

      expect(described_class.perform_now).to eq(0)
    end

    it "goes on with the other entities when one cannot be listed" do
      other = create(:entity, peppol_access_point: :b2brouter, peppol_participant_id: "0208:0333333333", peppol_credentials: { "api_key" => "test_other", "account_id" => "111", "webhook_secret" => "s" })
      stub_request(:get, %r{/accounts/111/invoices}).to_return(status: 401, body: "{}")
      listed(31)

      expect(described_class.perform_now).to eq(1)
      expect(ActsAsTenant.with_tenant(other) { Accounting::PeppolMessage.count }).to eq(0)
    end
  end
end
