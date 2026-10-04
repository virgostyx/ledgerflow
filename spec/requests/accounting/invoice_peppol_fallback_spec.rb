require "rails_helper"

# F06 step 5: a buyer that cannot be reached through Peppol is sent the PDF by e-mail instead, and the audit trail says the e-mail replaced the network.
RSpec.describe "Sending an invoice when Peppol cannot", type: :request do
  include_context "with_open_fiscal_year"
  include ActiveJob::TestHelper

  let(:accountant) { create(:user, role: :accountant) }
  let(:reader)     { create(:user, role: :manager) }
  let!(:membership)        { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:reader_membership) { create(:user_entity, :manager, user: reader, entity: entity) }
  let(:partner) { create(:partner, :with_vat, name: "Client SA", email: "billing@client.test") }
  let(:invoice) do
    inv = create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, invoice_number: "VTE2025/0001", invoice_date: Date.new(2025, 1, 15), due_date: Date.new(2025, 2, 15))
    create(:invoice_line, invoice: inv, account: create(:account, code: "700000"), description: "Service", quantity: 1, unit_price: "1000.00", vat_rate: "21.00", position: 1)
    inv.compute_totals
    inv.save!
    inv
  end

  before do
    entity.update!(peppol_access_point: :simulator, peppol_participant_id: "0208:0999999922", vat_number: "BE0999999922")
    sign_in accountant
  end

  it "offers the e-mail when the buyer has an address, and not when it has none" do
    get accounting_invoice_path(invoice)
    expect(response.body).to include("PDF by e-mail instead")

    partner.update!(email: nil)
    get accounting_invoice_path(invoice)
    expect(response.body).not_to include("PDF by e-mail instead")
  end

  it "sends the PDF to the buyer, and keeps in the audit trail that the e-mail replaced Peppol" do
    expect { post peppol_fallback_email_accounting_invoice_path(invoice) }.to change(Accounting::InvoiceEmail, :count).by(1)

    expect(Accounting::InvoiceEmail.last).to have_attributes(recipient: "billing@client.test", invoice_id: invoice.id)
    log = Accounting::AuditLog.where(action: "peppol_fallback_email", auditable_id: invoice.id).sole
    expect(log.payload).to include("recipient" => "billing@client.test", "success" => true)
    expect(log.user_id).to eq(accountant.id)
  end

  it "says so when the buyer has no e-mail address" do
    partner.update!(email: nil)
    expect { post peppol_fallback_email_accounting_invoice_path(invoice) }.not_to change(Accounting::InvoiceEmail, :count)

    expect(flash[:alert]).to include("Client SA")
  end

  it "is for those who may send through Peppol" do
    sign_in reader
    expect { post peppol_fallback_email_accounting_invoice_path(invoice) }.not_to change(Accounting::InvoiceEmail, :count)
  end

  it "tells the user, when the Access Point cannot be reached, that the invoice will be sent again by itself" do
    allow_any_instance_of(Peppol::AccessPoint::Simulator).to receive(:send_document).and_raise(Peppol::AccessPoint::TemporaryError, "down")

    post send_peppol_accounting_invoice_path(invoice)

    expect(flash[:notice]).to include("sent again by itself")
    expect(invoice.reload.peppol_status).to eq("not_sent")
  end
end
