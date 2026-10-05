require "rails_helper"

RSpec.describe "Closing: appropriation of the result", type: :request do
  include_context "with_open_fiscal_year"

  let(:owner)      { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:journal) { create(:journal, :sale) }
  let!(:misc) { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let(:year_end) { fiscal_year.end_date }
  let!(:bank)    { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:capital) { create(:account, code: "100000", label_fr: "Capital", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:result_account) { create(:account, code: "699000", label_fr: "Result", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:carry_account)  { create(:account, code: "130000", label_fr: "Carried forward", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:legal_reserve)  { create(:account, code: "130100", label_fr: "Legal reserve", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:next_year) { create(:fiscal_year, status: :pre_closing, year: fiscal_year.year + 1, start_date: year_end + 1, end_date: ((year_end + 1) >> 12) - 1) }
  let(:meeting) { (year_end + 90).iso8601 }

  def post_entry(date, *lines)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each { |account, side, amount| create(:journal_entry_line, journal_entry: entry, account: account, side => amount, (side == :debit ? :credit : :debit) => 0) }
    entry.post!
  end

  let!(:run) do
    entity.update!(vat_regime: :franchise)
    post_entry(fiscal_year.start_date + 1, [ bank, :debit, 100_000 ], [ capital, :credit, 100_000 ])
    post_entry(fiscal_year.start_date + 10, [ bank, :debit, 10_000 ], [ revenue, :credit, 10_000 ])
    open = Closing::OpenRun.call(fiscal_year: fiscal_year.reload, user: accountant)[:run]
    close_year!(run: open, accountant: accountant, owner: owner)
  end

  it "shows the figures and the proposal on a closed year, and prepares the draft of the next year when the person asks" do
    sign_in accountant
    get accounting_closing_run_path(run)
    expect(response.body).to include("Appropriation of the result", "Legal reserve now", "Proposed")
    expect(response.body).to include(Accounting::MoneyPresenter.new(BigDecimal("500")).format)

    expect { post appropriate_accounting_closing_run_path(run), params: { amount: "500", date: meeting, comment: "AGM 2027" } }.to change(Accounting::JournalEntry, :count).by(1)
    entry = Closing::Appropriation.entry_of(run)
    expect(response).to redirect_to(accounting_closing_run_path(run))
    expect(flash[:notice]).to include("draft of #{next_year.year}")
    expect(entry).to have_attributes(status: "draft", fiscal_year: next_year)

    get accounting_closing_run_path(run)
    expect(response.body).to include(accounting_journal_entry_path(entry), "Prepare it again")
  end

  it "says what is wrong rather than guessing: a bad date, an amount above the profit" do
    sign_in accountant
    post appropriate_accounting_closing_run_path(run), params: { amount: "500", date: "not a date" }
    expect(flash[:alert]).to match(/date of the general meeting/)
    post appropriate_accounting_closing_run_path(run), params: { amount: "20000", date: meeting }
    expect(flash[:alert]).to match(/exceeds the profit/)
    expect(Closing::Appropriation.entry_of(run)).to be_nil
  end

  it "is for a person who may prepare a closing: a reader reads the proposal and cannot ask" do
    sign_in reader
    get accounting_closing_run_path(run)
    expect(response.body).to include("Appropriation of the result").and not_include("Prepare the draft")
    post appropriate_accounting_closing_run_path(run), params: { amount: "500", date: meeting }
    expect(Closing::Appropriation.entry_of(run)).to be_nil
  end

  it "does not show a validated appropriation again as something to prepare" do
    sign_in owner
    entry = Closing::Appropriation.prepare!(run: run, user: owner, amount: "500", date: Date.iso8601(meeting), comment: "AGM")[:entry]
    Accounting::PostJournalEntry.call!(entry: entry)
    get accounting_closing_run_path(run)
    expect(response.body).to include("posted").and not_include("Prepare it again")
  end
end
