require "rails_helper"

RSpec.describe "Accounting::Reports journal_summary", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:journal)    { create(:journal, :purchase) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:expense_account)   { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:liability_account) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before { sign_in accountant }

  def post_numbered(number)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                   entry_date: fiscal_year.start_date + number,
                   reference: "#{journal.sequence_prefix}#{fiscal_year.year}/#{number.to_s.rjust(4, '0')}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: 10, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: liability_account, debit: 0, credit: 10)
    entry.post!
  end

  it "shows the per-journal per-month summary" do
    post_numbered(1)
    get accounting_reports_journal_summary_path(fiscal_year_id: fiscal_year.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(journal.code)
  end

  it "flags a numbering gap" do
    [ 1, 3 ].each { |n| post_numbered(n) }
    get accounting_reports_journal_summary_path(fiscal_year_id: fiscal_year.id)
    expect(response.body).to include("missing numbers 2")
  end
end
