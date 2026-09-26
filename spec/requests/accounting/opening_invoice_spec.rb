require "rails_helper"

RSpec.describe "Accounting opening invoice page", type: :request do
  include_context "with entity"
  include_context "with_open_fiscal_year"

  let(:admin) { create(:user, role: :admin) }
  let!(:membership) { create(:user_entity, :admin, user: admin, entity: entity) }

  before do
    create(:journal, journal_type: :misc, code: "OD", sequence_prefix: "OD")
    create(:account, code: "400000", account_class: 4, account_type: :asset, normal_balance: :debit, reconcilable: true)
    create(:account, code: "440000", account_class: 4, account_type: :liability, normal_balance: :credit, reconcilable: true)
    create(:account, code: "499000", account_class: 4, account_type: :asset, normal_balance: :debit)
    Accounting::ImportOpeningBalances.call(
      fiscal_year: fiscal_year,
      balances_csv: "account_code,debit,credit\n400000,300,0\n499000,0,300\n",
      invoices_csv: "type,partner_name,partner_vat,number,invoice_date,due_date,open_amount\ncustomer,Acme SA,,A1,2025-11-15,2025-12-15,300\n"
    )
    sign_in admin
  end

  it "shows the invoice without the actions that need invoice lines" do
    get accounting_invoice_path(Accounting::Invoice.find_by!(invoice_number: "A1"))
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A1")
    expect(response.body).not_to include("Create credit note")
    expect(response.body).not_to include("Duplicate")
    expect(response.body).not_to include("Download PDF")
    expect(response.body).not_to include("Make recurring")
  end
end
