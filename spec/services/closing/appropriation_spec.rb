require "rails_helper"

# F10, the appropriation of the result (decided 2026-10-05): after the closing, the legal reserve is proposed (5 % of the profit, until the reserve is 10 % of the
# capital) and written as a DRAFT of the next year, dated the day of the general meeting; the rest of the profit stays carried forward. Nothing else is covered yet.
RSpec.describe Closing::Appropriation do
  include_context "with_open_fiscal_year"

  let(:owner)      { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:journal) { create(:journal, :sale) }
  let!(:misc) { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let(:year_end) { fiscal_year.end_date }

  let!(:bank)      { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:capital)   { create(:account, code: "100000", label_fr: "Capital", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:revenue)   { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:expense)   { create(:account, code: "610000", label_fr: "Services", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:result_account) { create(:account, code: "699000", label_fr: "Result", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:carry_account)  { create(:account, code: "140100", label_fr: "Carried forward", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:legal_reserve)  { create(:account, code: "130100", label_fr: "Legal reserve", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:next_year) { create(:fiscal_year, status: :pre_closing, year: fiscal_year.year + 1, start_date: year_end + 1, end_date: ((year_end + 1) >> 12) - 1) }
  let(:meeting) { year_end + 90 }

  def post(date, *lines)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each { |account, side, amount| create(:journal_entry_line, journal_entry: entry, account: account, side => amount, (side == :debit ? :credit : :debit) => 0) }
    entry.post!
  end

  # capital 100 000, profit 10 000 (sales 12 000, costs 2 000), unless the example says otherwise
  let(:sales) { 12_000 }
  let(:costs) { 2_000 }
  let(:existing_reserve) { 0 }

  def close_with_profit!
    entity.update!(vat_regime: :franchise, legal_form: "SRL") # (the factory makes an ASBL, which has no legal reserve)
    post(fiscal_year.start_date + 1, [ bank, :debit, 100_000 ], [ capital, :credit, 100_000 ])
    post(fiscal_year.start_date + 5, [ bank, :debit, existing_reserve ], [ legal_reserve, :credit, existing_reserve ]) if existing_reserve.positive?
    post(fiscal_year.start_date + 10, [ bank, :debit, sales ], [ revenue, :credit, sales ])
    post(fiscal_year.start_date + 20, [ expense, :debit, costs ], [ bank, :credit, costs ])
    run = Closing::OpenRun.call(fiscal_year: fiscal_year.reload, user: accountant)[:run]
    close_year!(run: run, accountant: accountant, owner: owner)
  end

  let(:run) { close_with_profit! }

  describe ".proposal" do
    it "proposes 5 % of the profit for the legal reserve, with how it was worked out" do
      proposal = described_class.proposal(run)
      expect(proposal).to include(profit: BigDecimal("10000"), capital: BigDecimal("100000"), reserve: BigDecimal("0"), ceiling: BigDecimal("10000"), proposed: BigDecimal("500"),
                                  carry_account: "140100", reserve_account: "130100")
      expect(proposal[:problem]).to be_nil
    end

    context "when the reserve already holds 9 800 of the 10 000 it may reach" do
      let(:existing_reserve) { 9_800 }

      it "stops at 10 % of the capital: only what is missing from the reserve is proposed" do
        expect(described_class.proposal(run)).to include(reserve: BigDecimal("9800"), ceiling: BigDecimal("200"), proposed: BigDecimal("200"))
      end
    end

    context "when the reserve is full" do
      let(:existing_reserve) { 10_000 }

      it "proposes nothing, and says why" do
        expect(described_class.proposal(run)).to include(proposed: BigDecimal("0"), problem: "The legal reserve already holds 10 % of the capital.")
      end
    end

    context "in a year with a loss" do
      let(:sales) { 1_000 }
      let(:costs) { 3_000 }

      it "proposes nothing" do
        expect(described_class.proposal(run)).to include(proposed: BigDecimal("0"), problem: "There is no profit to appropriate.")
      end
    end

    it "does not apply to an association: its chart has no legal reserve" do
      closed = run
      entity.update!(legal_form: "ASBL")
      expect(described_class.proposal(closed.reload)).to include(proposed: BigDecimal("0"), problem: "The legal reserve does not apply to an association: its chart has no such account.")
    end

    it "is only for a closed year" do
      open_run = Closing::OpenRun.call(fiscal_year: fiscal_year.reload, user: accountant)[:run]
      expect(described_class.proposal(open_run)[:problem]).to eq("The year is not closed yet.")
    end
  end

  describe ".prepare!" do
    it "writes the legal reserve as a DRAFT of the next year, dated the day of the meeting: debit the carried profit, credit the reserve" do
      result = described_class.prepare!(run: run, user: accountant, amount: "500", date: meeting, comment: "General meeting of the shareholders")
      expect(result).to be_success
      entry = result[:entry]
      expect(entry).to be_draft
      expect(entry).to have_attributes(fiscal_year: next_year, entry_date: meeting, source_type: Accounting::JournalEntry::APPROPRIATION_SOURCE, source_id: run.id, created_by: accountant)
      expect(entry.lines.map { |l| [ l.account.code, l.debit, l.credit ] }).to match_array([ [ "140100", 500, 0 ], [ "130100", 0, 500 ] ])
      expect(entry.description).to include("Appropriation of the result of #{fiscal_year.year}", "General meeting")
      expect(Accounting::AuditLog.where(action: "result_appropriation_prepared").last.payload).to include("amount" => "500.0", "fiscal_year" => fiscal_year.year)
    end

    it "is written again, not added to, when it is prepared again as long as it is a draft" do
      described_class.prepare!(run: run, user: accountant, amount: "500", date: meeting, comment: "First")
      expect { described_class.prepare!(run: run, user: accountant, amount: "300", date: meeting + 1, comment: "Second") }.not_to change { Accounting::JournalEntry.where(source_type: Accounting::JournalEntry::APPROPRIATION_SOURCE).count }
      expect(described_class.entry_of(run).lines.sum(:debit)).to eq(300)
    end

    it "refuses an amount that is not positive or that exceeds the profit, a date outside the next year, and a missing reserve account" do
      refuse = ->(**args) { described_class.prepare!(run: run, user: accountant, amount: "500", date: meeting, comment: "x", **args) }
      expect(refuse.(amount: "0")).to be_failure
      expect(refuse.(amount: "-5")).to be_failure
      expect(refuse.(amount: "abc").message).to match(/amount/)
      expect(refuse.(amount: "10000.01").message).to match(/exceeds the profit/)
      expect(refuse.(date: year_end).message).to match(/after the end of the year/)
      expect(refuse.(date: next_year.end_date + 5).message).to match(/next fiscal year/)
      legal_reserve.update_columns(code: "139999")
      expect(refuse.().message).to match(/130100.*Legal reserve/)
      expect(Accounting::JournalEntry.where(source_type: Accounting::JournalEntry::APPROPRIATION_SOURCE)).to be_empty
    end

    it "is for a person who may prepare a closing, and for a closed year" do
      assistant = create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) }
      expect(described_class.prepare!(run: run, user: assistant, amount: "500", date: meeting, comment: "x")).to be_failure
      reopened = Closing::Reopen.call(run: run.reload, user: owner, reason: "Late invoice")
      expect(reopened).to be_success
      expect(described_class.prepare!(run: run.reload, user: accountant, amount: "500", date: meeting, comment: "x").message).to match(/not closed/)
    end

    it "does not touch a validated appropriation: it is reversed first" do
      entry = described_class.prepare!(run: run, user: accountant, amount: "500", date: meeting, comment: "First")[:entry]
      Accounting::PostJournalEntry.call!(entry: entry)
      result = described_class.prepare!(run: run, user: accountant, amount: "400", date: meeting, comment: "Second")
      expect(result.message).to match(/already booked.*reverse it first/)
      expect(entry.reload).to be_posted
    end
  end

  describe "the reopening of the year" do
    it "takes the draft appropriation with it, and refuses while it is booked" do
      entry = described_class.prepare!(run: run, user: accountant, amount: "500", date: meeting, comment: "First")[:entry]
      Accounting::PostJournalEntry.call!(entry: entry)
      refused = Closing::Reopen.call(run: run.reload, user: owner, reason: "Late invoice")
      expect(refused).to be_failure
      expect(refused.message).to match(/appropriation of the result was booked/)
      expect(fiscal_year.reload).to be_closed

      expect(Accounting::ReverseJournalEntry.call(entry: entry.reload, reason: "Meeting postponed", user: owner)).to be_success
      expect(Closing::Reopen.call(run: run.reload, user: owner, reason: "Late invoice")).to be_success
    end

    it "deletes a draft appropriation when the year is reopened" do
      described_class.prepare!(run: run, user: accountant, amount: "500", date: meeting, comment: "First")
      expect(Closing::Reopen.call(run: run.reload, user: owner, reason: "Late invoice")).to be_success
      expect(described_class.entry_of(run)).to be_nil
    end
  end
end
