require "rails_helper"

# F06 step 4: the screens of what went through Peppol: received invoices (look, work on again, give a supplier, put aside), sent invoices (follow,
# send again), the board of the period; and who may do what.
RSpec.describe "Peppol messages", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"
  include_context "with_suspense_account"

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let(:reader)     { create(:user, role: :manager) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let!(:reader_membership)     { create(:user_entity, :manager, user: reader, entity: entity) }
  let!(:purchase_journal) { create(:journal, :purchase) }

  def example(name) = Rails.root.join("spec/fixtures/files/peppol", name).read
  def take(xml, id = SecureRandom.hex(4)) = Peppol::ReceiveMessage.call(event: Peppol::Event.new(kind: :received, message_id: id, receiver: "0208:0999999999", xml: xml, sender: "0208:0123456749"))[:message]

  before { sign_in accountant }

  # the number in the card of the board with this label
  def card(label) = response.body[%r{#{Regexp.escape(label)}</div><div[^>]*>(\d+)<}, 1].to_i

  describe "the lists and the board" do
    let!(:drafted) { take(PeppolUbl.invoice(number: "SUP-OK")) }
    let!(:waiting) { take(example("vat-category-E.xml")) } # GBP, no rate

    it "lists the received messages, with their status and why they wait" do
      get accounting_peppol_messages_path

      expect(response.body).to include("SUP-OK").and include("Needs review").and include("exchange rate")
    end

    it "counts the period on a board, and what waits whatever the period" do
      get accounting_peppol_messages_path

      expect([ card("Received"), card("Drafted"), card("Waiting for review"), card("Sent") ]).to eq([ 2, 1, 1, 0 ])
    end

    it "filters by status and by dates" do
      get accounting_peppol_messages_path, params: { status: "needs_review" }
      expect(response.body).to include("exchange rate").and not_include("SUP-OK")

      get accounting_peppol_messages_path, params: { from: "2020-01-01", to: "2020-01-31" }
      expect(response.body).not_to include("SUP-OK")
    end

    it "lists the sent messages apart" do
      Accounting::PeppolMessage.create!(direction: :outbound, message_id: "OUT-1", status: :failed, receiver_id: "0208:0888888888", problems: [ "Receiver rejected it" ], xml: "<Invoice/>")

      get accounting_peppol_messages_path(direction: "outbound")

      expect(response.body).to include("0208:0888888888").and include("Receiver rejected it").and not_include("SUP-OK")
      expect([ card("Sent"), card("Failed") ]).to eq([ 1, 1 ])
    end
  end

  describe "a message" do
    it "shows the PDF of the supplier beside the XML when there is one" do
      pdf = Base64.strict_encode64("%PDF-1.4\nbody\n%%EOF\n")
      message = take(PeppolUbl.invoice(extra: "<cac:AdditionalDocumentReference><cbc:ID>p</cbc:ID><cac:Attachment><cbc:EmbeddedDocumentBinaryObject mimeCode=\"application/pdf\" filename=\"f.pdf\">#{pdf}</cbc:EmbeddedDocumentBinaryObject></cac:Attachment></cac:AdditionalDocumentReference>"))

      get accounting_peppol_message_path(message)
      expect(response.body).to include(pdf_accounting_peppol_message_path(message)).and include("The XML as received")
      expect(response.body).not_to include(pdf) # the base64 is not shown

      get pdf_accounting_peppol_message_path(message)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
    end

    it "shows a readable rendering of the XML when there is no PDF" do
      message = take(PeppolUbl.invoice(number: "SUP-READ", lines: [ [ 100, "S", 21 ] ]))

      get accounting_peppol_message_path(message)

      expect(response.body).to include("Readable rendering").and include("SUP-READ").and include("121.0")
      get pdf_accounting_peppol_message_path(message)
      expect(response).to have_http_status(:not_found)
    end

    it "shows a message that cannot be read, with what is wrong" do
      message = take("<Invoice><nothing/></Invoice>")

      get accounting_peppol_message_path(message)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This message waits").and include("no number")
    end
  end

  describe "working on a waiting message" do
    let!(:waiting) { take(example("vat-category-E.xml")) }

    it "drafts it again once the cause is dealt with (the exchange rate entered), and audits it" do
      Accounting::ExchangeRate.create!(currency: "GBP", rate_date: Date.new(2017, 1, 1), rate: BigDecimal("1.15"))

      post reprocess_accounting_peppol_message_path(waiting)

      expect(waiting.reload).to have_attributes(status: "processed", problems: [])
      expect(waiting.invoice).to have_attributes(currency: "GBP", status: "draft")
      expect(Accounting::AuditLog.where(auditable_type: "Accounting::PeppolMessage", auditable_id: waiting.id, action: "peppol_message_reprocessed").sole.user_id).to eq(accountant.id)
    end

    it "says it still waits when the cause is still there" do
      post reprocess_accounting_peppol_message_path(waiting)

      expect(flash[:notice]).to include("Still waiting").and include("exchange rate")
      expect(waiting.reload).to be_needs_review
    end

    it "works on several at once" do
      other = take(example("vat-category-Z.xml"))
      Accounting::ExchangeRate.create!(currency: "GBP", rate_date: Date.new(2017, 1, 1), rate: BigDecimal("1.15"))

      post reprocess_all_accounting_peppol_messages_path, params: { message_ids: [ waiting.id, other.id ] }

      expect(flash[:notice]).to include("2 of 2")
      expect([ waiting, other ].map { |m| m.reload.status }).to eq(%w[processed processed])
    end

    it "refuses to work again on a message that is not waiting" do
      done = take(PeppolUbl.invoice)

      post reprocess_accounting_peppol_message_path(done)

      expect(flash[:alert]).to include("waits for review")
    end

    it "is given its supplier when several partners shared an identifier, then drafted" do
      create(:partner, partner_type: :supplier, name: "Twin A", iban: "BE68539007547034")
      pick = create(:partner, partner_type: :supplier, name: "Twin B", iban: "BE68539007547034")
      twins = take(PeppolUbl.invoice(vat: nil, iban: "BE68539007547034", number: "TWIN-1"))
      expect(twins).to be_needs_review

      post assign_supplier_accounting_peppol_message_path(twins), params: { partner_id: pick.id }

      expect(twins.reload).to have_attributes(status: "processed", partner_id: pick.id)
      expect(twins.invoice.partner).to eq(pick)
    end

    it "is put aside with a reason, never deleted, and audited" do
      post dismiss_accounting_peppol_message_path(waiting), params: { reason: "Wrong addressee" }

      expect(waiting.reload).to be_dismissed
      expect(waiting.note).to include("Wrong addressee")
      expect(waiting.xml).to be_present
      expect(Accounting::AuditLog.where(action: "peppol_message_dismissed").sole.reason).to eq("Wrong addressee")
    end

    it "is not put aside without a reason" do
      post dismiss_accounting_peppol_message_path(waiting), params: { reason: " " }

      expect(waiting.reload).to be_needs_review
      expect(flash[:alert]).to include("why")
    end
  end

  describe "sending again" do
    let(:partner) { create(:partner, :with_vat, name: "Client SA") }
    let(:invoice) do
      inv = create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, invoice_number: "VTE2026/0001", invoice_date: Date.new(2026, 1, 15))
      create(:invoice_line, invoice: inv, account: account_700, description: "Service", quantity: 1, unit_price: "1000.00", vat_rate: "21.00", position: 1)
      inv.compute_totals
      inv.save!
      inv
    end
    let!(:failed) do
      entity.update!(peppol_access_point: :simulator, peppol_participant_id: "0208:0999999999", vat_number: "BE0999999999")
      Accounting::PeppolMessage.create!(direction: :outbound, message_id: "OUT-1", status: :failed, invoice: invoice, problems: [ "boom" ], xml: "<Invoice/>")
    end

    it "sends a failed invoice again, and audits it" do
      post resend_accounting_peppol_message_path(failed)

      expect(flash[:notice]).to eq("Sent again")
      expect(invoice.reload.peppol_status).to eq("queued")
      expect(Accounting::AuditLog.where(action: "peppol_resent").sole.payload).to include("success" => true)
    end

    it "does not send what did not fail" do
      failed.update!(status: :delivered)
      post resend_accounting_peppol_message_path(failed)

      expect(flash[:alert]).to include("failed")
    end
  end

  describe "the test environment" do
    it "is announced on the screens when the Access Point is a simulation" do
      entity.update!(peppol_access_point: :simulator, peppol_participant_id: "0208:0999999999")
      get accounting_peppol_messages_path

      expect(response.body).to include("Test environment")
    end

    it "is announced for a B2Brouter sandbox key, not for a live one" do
      entity.update!(peppol_access_point: :b2brouter, peppol_participant_id: "0208:0999999999",
                     peppol_credentials: { "api_key" => "test_abc", "account_id" => "1", "webhook_secret" => "s" })
      get accounting_peppol_messages_path
      expect(response.body).to include("Test environment")

      entity.update!(peppol_credentials: { "api_key" => "live_abc", "account_id" => "1", "webhook_secret" => "s" })
      get accounting_peppol_messages_path
      expect(response.body).not_to include("Test environment")
    end
  end

  describe "who may" do
    let!(:waiting) { take(example("vat-category-E.xml")) }

    it "lets an assistant look, work on again and put aside, but not send" do
      sign_in assistant
      get accounting_peppol_messages_path
      expect(response).to have_http_status(:ok)

      post dismiss_accounting_peppol_message_path(waiting), params: { reason: "x" }
      expect(waiting.reload).to be_dismissed

      post resend_accounting_peppol_message_path(waiting)
      expect(Accounting::AuditLog.where(action: "peppol_resent")).to be_empty
    end

    it "closes the screens to a reader" do
      sign_in reader
      get accounting_peppol_messages_path
      expect(response).not_to have_http_status(:ok)

      post reprocess_accounting_peppol_message_path(waiting)
      expect(waiting.reload).to be_needs_review
    end

    it "does not show the messages of another entity" do
      other = create(:entity)
      foreign = ActsAsTenant.with_tenant(other) { Accounting::PeppolMessage.create!(direction: :inbound, message_id: "FOREIGN-1", status: :processed, xml: "<Invoice/>") }

      get accounting_peppol_message_path(foreign)

      expect(response).not_to have_http_status(:ok)
    end
  end
end
