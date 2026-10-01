require "rails_helper"

RSpec.describe "Returning an invoice to the project manager", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:supplier) { create(:partner, :supplier) }
  let(:draft) { create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year, external_digest: "x") }

  before { sign_in accountant }

  it "offers the accountant a form with a reason, on a BudgetFlow draft" do
    get accounting_invoice_path(draft)

    expect(response.body).to include("Return to project manager")
  end

  it "returns the invoice with the reason" do
    post return_invoice_accounting_invoice_path(draft), params: { reason: "Wrong budget line" }

    expect(response).to redirect_to(accounting_purchases_path)
    expect(draft.reload).to be_cancelled
    expect(Accounting::InvoiceEvent.where(invoice_id: draft.id, event_type: "returned").last.payload["reason"]).to eq("Wrong budget line")
  end

  it "asks for a reason" do
    post return_invoice_accounting_invoice_path(draft), params: { reason: "" }

    expect(response).to redirect_to(accounting_invoice_path(draft))
    expect(flash[:alert]).to match(/reason/i)
    expect(draft.reload).to be_draft
  end

  it "is not offered on a draft typed in the UI" do
    typed = create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)

    get accounting_invoice_path(typed)

    expect(response.body).not_to include("Return to project manager")
  end

  it "is reserved to administrators and accountants" do
    manager = create(:user, role: :manager)
    create(:user_entity, :manager, user: manager, entity: entity)
    sign_in manager

    get accounting_invoice_path(draft)
    expect(response.body).not_to include("Return to project manager")

    post return_invoice_accounting_invoice_path(draft), params: { reason: "x" }
    expect(draft.reload).to be_draft
  end

  it "does not exist for an entity that does not use BudgetFlow" do
    entity.update!(budgetflow_enabled: false)

    get accounting_invoice_path(draft)
    expect(response.body).not_to include("Return to project manager")

    post return_invoice_accounting_invoice_path(draft), params: { reason: "x" }
    expect(response).to have_http_status(:not_found)
    expect(draft.reload).to be_draft
  end
end

RSpec.describe "Returning a posted BudgetFlow invoice", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:purchase) { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: "BF-P-1") }
  let(:posted) do
    d = Accounting::ExternalInvoice.upsert(
      external_ref: "BF-I-1", partner_external_ref: "BF-P-1", invoice_type: "supplier", invoice_date: Date.current.to_s, post: false,
      lines: [ { account_code: "604000", description: "X", quantity: "1", unit_price: "100", vat_rate: "21" } ]
    ).invoice
    Accounting::PostInvoice.call(invoice: d)
    d.reload
  end

  before { sign_in accountant }

  it "offers Return instead of Cancel: cancelling alone would leave BudgetFlow unaware" do
    get accounting_invoice_path(posted)

    expect(response.body).to include("Return to project manager")
    expect(response.body).not_to include("Cancel invoice")
  end

  it "refuses a direct cancellation of such an invoice" do
    post cancel_invoice_accounting_invoice_path(posted)

    expect(posted.reload).to be_posted
  end

  it "reverses the invoice and returns it with the reason" do
    post return_invoice_accounting_invoice_path(posted), params: { reason: "Amount to correct" }

    expect(response).to redirect_to(accounting_purchases_path)
    expect(posted.reload).to be_cancelled
    expect(Accounting::InvoiceEvent.where(invoice_id: posted.id, event_type: "returned")).to exist
  end

  it "still lets an invoice typed in the UI be cancelled as usual" do
    typed = create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)
    Accounting::PostInvoice.call(invoice: typed) # may fail for lack of lines: only the button matters here
    typed.update_columns(status: Accounting::Invoice.statuses[:posted]) unless typed.reload.posted?

    get accounting_invoice_path(typed)

    expect(response.body).to include("Cancel invoice")
  end

  it "keeps Cancel for an entity that does not use BudgetFlow" do
    entity.update!(budgetflow_enabled: false)

    get accounting_invoice_path(posted)

    expect(response.body).to include("Cancel invoice")
    expect(response.body).not_to include("Return to project manager")
  end
end
