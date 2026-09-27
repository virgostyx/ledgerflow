require "rails_helper"

RSpec.describe "Accounting::Reports unlettered_lines", type: :request, bullet_strict: true do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:journal)    { create(:journal, :purchase) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:other_account)    { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }
  let(:alice) { create(:partner, name: "Alice") }

  before { sign_in accountant }

  def post_line(side:, amount:, partner: alice)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    other = side == :debit ? :credit : :debit
    create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: partner,
           side => BigDecimal(amount.to_s), other => 0)
    create(:journal_entry_line, journal_entry: entry, account: other_account, other => BigDecimal(amount.to_s), side => 0)
    entry.post!
  end

  it "returns 200 and lists open lines grouped by partner" do
    post_line(side: :debit, amount: 100)
    get accounting_reports_unlettered_lines_path(fiscal_year_id: fiscal_year.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Alice")
  end

  it "flags a balanced unlettered group" do
    post_line(side: :debit, amount: 50)
    post_line(side: :credit, amount: 50)
    get accounting_reports_unlettered_lines_path(fiscal_year_id: fiscal_year.id)
    expect(response.body).to include("Balanced groups left unlettered")
  end

  it "returns 200 with an invalid as_of date" do
    get accounting_reports_unlettered_lines_path(fiscal_year_id: fiscal_year.id, as_of: "invalid")
    expect(response).to have_http_status(:ok)
  end

  it "is linked from the aged balance report's total" do
    get accounting_reports_aged_balance_path(fiscal_year_id: fiscal_year.id, kind: "customer")
    expect(response.body).to match(%r{href="[^"]*unlettered_lines\?[^"]*kind=customer[^"]*"})
  end
end
