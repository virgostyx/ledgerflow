require "rails_helper"

RSpec.describe "Accounting::Accruals", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:auditor)    { create(:user, role: :auditor) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:auditor_membership)    { create(:user_entity, :auditor, user: auditor, entity: entity) }

  let!(:misc)    { create(:journal, journal_type: :misc) }
  let!(:expense) { create(:account, code: "613000", label_fr: "Insurance", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:a490)    { create(:account, code: "490100", label_fr: "Deferred charges", account_class: 4, account_type: :asset, normal_balance: :debit) }

  before { sign_in accountant }

  let(:params) do
    { accounting_accrual: { accrual_type: "deferred_charge", description: "Insurance", total_amount: "1200", pl_account_id: expense.id,
                            period_start: Date.new(fiscal_year.end_date.year, 10, 1).to_s, period_end: Date.new(fiscal_year.end_date.year + 1, 9, 30).to_s } }
  end

  it "renders the report page" do
    get accounting_accruals_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Closing regularizations", "Regularizations vs ledger (I11)")
  end

  it "creates a regularization with the account of its type, then books it as a draft" do
    expect { post accounting_accruals_path, params: params }.to change(Accounting::Accrual, :count).by(1)
    accrual = Accounting::Accrual.last
    expect(accrual.accrual_account).to eq(a490)

    expect { post book_accounting_accrual_path(accrual) }.to change(Accounting::JournalEntry, :count).by(1)
    expect(accrual.reload.journal_entry).to be_draft
    get accounting_accruals_path
    expect(response.body).to include("Missing reversal", "Draft entry")
  end

  it "rejects an invalid regularization and re-renders the form" do
    post accounting_accruals_path, params: params.deep_merge(accounting_accrual: { total_amount: "0" })
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "refuses to delete a booked regularization but deletes a pending one" do
    post accounting_accruals_path, params: params
    accrual = Accounting::Accrual.last
    post book_accounting_accrual_path(accrual)
    expect { delete accounting_accrual_path(accrual) }.not_to change(Accounting::Accrual, :count)
    pending = create(:accrual, fiscal_year: fiscal_year, pl_account: expense, accrual_account: a490)
    expect { delete accounting_accrual_path(pending) }.to change(Accounting::Accrual, :count).by(-1)
  end

  it "flashes the reason when reversing without a next fiscal year" do
    post accounting_accruals_path, params: params
    accrual = Accounting::Accrual.last
    post book_accounting_accrual_path(accrual)
    post reverse_accounting_accrual_path(accrual)
    expect(flash[:alert]).to include("next fiscal year")
  end

  it "keeps the auditor out" do
    sign_out accountant
    sign_in auditor
    get accounting_accruals_path
    expect(response).not_to have_http_status(:ok)
  end
end
