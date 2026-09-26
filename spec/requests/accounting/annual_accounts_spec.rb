require "rails_helper"

RSpec.describe "Accounting::Reports annual accounts", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:auditor)    { create(:user, role: :auditor) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:auditor_membership)    { create(:user_entity, :auditor, user: auditor, entity: entity) }
  let(:journal) { create(:journal, :purchase) }

  let!(:bank)    { create(:account, code: "550000", label_fr: "Banque", account_type: :asset, normal_balance: :debit, account_class: 5) }
  let!(:capital) { create(:account, code: "101000", label_fr: "Capital", account_type: :equity, normal_balance: :credit, account_class: 1) }
  let!(:sales)   { create(:account, code: "700000", label_fr: "Ventes", account_type: :revenue, normal_balance: :credit, account_class: 7) }
  let!(:odd)     { create(:account, code: "590000", label_fr: "Virements internes", account_type: :asset, normal_balance: :debit, account_class: 5) }

  before do
    sign_in accountant
    [ [ bank, capital, 10_000 ], [ bank, sales, 2_500 ] ].each do |debit, credit, amount|
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 5)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: debit, debit: amount, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: credit, debit: 0, credit: amount)
      entry.post!
    end
  end

  it "shows the balance sheet and the income statement by legal heading" do
    get accounting_reports_annual_accounts_path
    money = ->(n) { Accounting::MoneyPresenter.new(n).format }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Annual accounts", "TOTAL ASSETS", "TOTAL LIABILITIES", "Operating profit (loss)", "Profit (loss) for the period")
    expect(response.body).to include(money.call(12_500), money.call(2_500))
  end

  it "says which model it follows and that it is not validated" do
    get accounting_reports_annual_accounts_path
    expect(response.body).to include("abridged model", "not been validated")
  end

  it "reports that the balance sheet balances" do
    get accounting_reports_annual_accounts_path
    expect(response.body).to include("balanced")
    expect(response.body).not_to include("Accounts that fit no heading")
  end

  it "warns of an imbalance and lists the accounts that fit no heading" do
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 6)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: odd, debit: 70, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: bank, debit: 0, credit: 70)
    entry.post!

    get accounting_reports_annual_accounts_path
    expect(response.body).to include("does not balance", "Accounts that fit no heading", "590000")
  end

  it "shows the previous fiscal year next to the current one" do
    previous = create(:fiscal_year, year: fiscal_year.year - 1, start_date: fiscal_year.start_date - 1.year,
                      end_date: fiscal_year.start_date - 1.day, status: :closed)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: previous, entry_date: previous.start_date + 3)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: bank, debit: 900, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: sales, debit: 0, credit: 900)
    entry.post!

    get accounting_reports_annual_accounts_path(fiscal_year_id: fiscal_year.id)
    expect(response.body).to include(previous.year.to_s, Accounting::MoneyPresenter.new(900).format)
  end

  it "exports the same figures as a spreadsheet" do
    get accounting_reports_annual_accounts_path(format: :xlsx)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    expect(response.body.bytesize).to be > 1_000
    expect(response.headers["Content-Disposition"]).to include("annual_accounts_#{fiscal_year.year}.xlsx")
  end

  it "is refused to an auditor, like the other financial reports" do
    sign_in auditor
    get accounting_reports_annual_accounts_path
    expect(response).to have_http_status(:redirect)
    expect(response.body).not_to include("TOTAL ASSETS")
  end
end
