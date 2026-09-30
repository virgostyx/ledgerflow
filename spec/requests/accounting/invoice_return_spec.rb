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
