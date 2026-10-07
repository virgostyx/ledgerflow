require "rails_helper"

# A05: "Explain" on a figure of a report opens the assistant on that figure.
RSpec.describe "The Explain button of the aged balance (A05)", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:customers) { create(:account, :customer, reconcilable: true) }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Ventes", account_type: :revenue, normal_balance: :credit) }
  let(:partner) { create(:partner, name: "Acme SA") }

  before do
    sign_in accountant
    entry = create(:journal_entry, :draft, journal: create(:journal, :sale), fiscal_year: fiscal_year, entry_date: Date.current)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: customers, partner: partner, invoice: create(:invoice, :posted, fiscal_year: fiscal_year, due_date: Date.current + 10), debit: 100, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: revenue, debit: 0, credit: 100)
    entry.post!
  end

  it "is on each partner's total when the assistant is available, with the reference of the cell" do
    enable_agent!

    get accounting_reports_aged_balance_path(kind: "customer", as_of: Date.current.iso8601)

    expect(response.body).to include('value="R04"').or include("R04")
    expect(response.body).to include("#{Date.current.iso8601}:customer:#{partner.id}", "Explain")
    expect(response.body).to include('data-controller="agent-explain"')
  end

  it "is not there when the assistant is off" do
    get accounting_reports_aged_balance_path(kind: "customer", as_of: Date.current.iso8601)

    expect(response.body).not_to include("agent-explain")
  end
end
