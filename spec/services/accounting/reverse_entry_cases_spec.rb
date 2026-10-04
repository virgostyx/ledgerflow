require "rails_helper"

# F07 §10, extourne: the date (open period, locked period, closed year), VAT regularisation, lettered lines (confirmed unlettering), a
# reversal of a reversal, scheduled reversals (auto_reverse_on) as drafts.
RSpec.describe Accounting::ReverseJournalEntry, "cases" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user)    { create(:user, role: :accountant) }
  let(:journal) { create(:journal, :cash) }
  let(:supplier) { create(:partner, :supplier) }
  let(:today)   { fiscal_year.start_date + 100 }

  def post_entry(date: today, debit: 121, credit: 121, partner: nil, fy: fiscal_year, **attrs)
    entry = create(:journal_entry, journal: journal, fiscal_year: fy, entry_date: date, status: :draft, **attrs)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(debit.to_s), credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: partner, debit: 0, credit: BigDecimal(credit.to_s))
    Accounting::PostJournalEntry.call!(entry: entry)
    entry.reload
  end

  def reverse(entry, **options) = described_class.call(entry: entry, reason: "wrong account", user: user, **options)

  describe "the date" do
    it "is the date of the entry when its period is open" do
      result = reverse(post_entry)

      expect(result).to be_success
      expect(result[:reversal]).to have_attributes(entry_date: today, fiscal_year_id: fiscal_year.id, vat_regularisation: false)
      expect(result[:warnings]).to be_empty
    end

    it "can be chosen, in an open period" do
      result = reverse(post_entry, date: today + 10)

      expect(result[:reversal].entry_date).to eq(today + 10)
    end

    it "refuses a chosen date in a locked period" do
      create(:period_lock, starts_on: today + 20, ends_on: today + 30)

      expect(reverse(post_entry, date: today + 25)).to be_failure
    end

    it "refuses a chosen date outside every open fiscal year" do
      expect(reverse(post_entry, date: fiscal_year.end_date + 5)).to be_failure
    end

    it "moves to the first day after a locked period, and says so" do
      entry = post_entry
      create(:period_lock, starts_on: today - 10, ends_on: today + 10)

      result = reverse(entry)
      expect(result.message).to be_blank

      expect(result[:reversal].entry_date).to eq(today + 11)
      expect(result[:reversal].vat_regularisation).to be(false)
      expect(result[:warnings].join).to include("locked")
    end

    it "marks a reversal moved out of a filed VAT period as a regularisation" do
      entry = post_entry
      create(:period_lock, kind: :vat, starts_on: today - 10, ends_on: today + 10)

      result = reverse(entry)

      expect(result[:reversal]).to have_attributes(entry_date: today + 11, vat_regularisation: true)
      expect(result[:warnings].join).to include("VAT")
    end

    it "goes to the first day of the next open fiscal year when the year of the entry is closed" do
      entry = post_entry
      fiscal_year.update_columns(status: Accounting::FiscalYear.statuses[:closed])
      next_year = create(:fiscal_year, year: fiscal_year.year + 1, start_date: fiscal_year.end_date + 1, end_date: fiscal_year.end_date + 365, status: :open)

      result = reverse(entry)

      expect(result[:reversal]).to have_attributes(entry_date: next_year.start_date, fiscal_year_id: next_year.id)
      expect(result[:warnings].join).to include("closed")
    end

    it "refuses when no fiscal year is open" do
      entry = post_entry
      fiscal_year.update_columns(status: Accounting::FiscalYear.statuses[:closed])

      expect(reverse(entry)).to be_failure
    end
  end

  describe "an entry already reversed" do
    it "is refused a second reversal while the first is active" do
      entry = post_entry
      reverse(entry)

      expect(reverse(entry.reload)).to be_failure
    end

    it "is refused a second reversal while the first is still a draft" do
      entry = post_entry
      reverse(entry, draft: true)

      expect(reverse(entry.reload)).to be_failure
    end

    it "lets the reversal itself be reversed, which books the original again" do
      entry = post_entry
      first = reverse(entry)[:reversal]

      again = reverse(first.reload)[:reversal]

      expect(again.lines.map { |l| [ l.account_id, l.debit, l.credit ] }).to match_array(entry.lines.map { |l| [ l.account_id, l.debit, l.credit ] })
    end

    it "nets to zero on every account, the two entries together" do
      entry = post_entry
      reversal = reverse(entry)[:reversal]
      lines = Accounting::JournalEntryLine.where(journal_entry_id: [ entry.id, reversal.id ])

      expect(lines.group(:account_id).sum("debit - credit").values).to all(eq(0))
    end
  end

  describe "lettered lines" do
    let(:invoice_entry) { post_entry(partner: supplier) }
    let!(:payment) do
      entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: today + 1, status: :draft)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, debit: 121, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: account_570, debit: 0, credit: 121)
      Accounting::PostJournalEntry.call!(entry: entry)
      entry.lines.find_by(account: account_440)
    end
    let(:payable) { invoice_entry.lines.find_by(account: account_440) }

    before { Accounting::LetterLines.call(lines: [ payable, payment ], user: user) }

    it "is refused without the confirmation of the unlettering, and nothing changes" do
      result = reverse(invoice_entry)

      expect(result).to be_failure
      expect(result.message).to include("confirm")
      expect(payable.reload.lettering_id).to be_present
      expect(invoice_entry.reload).to be_posted
    end

    it "unletters first, with the same reason, once confirmed" do
      result = reverse(invoice_entry, confirm_unletter: true)

      expect(result).to be_success
      expect(payable.reload.lettering_id).to be_nil
      expect(payment.reload.lettering_id).to be_nil
      expect(Accounting::LetteringEvent.where(action: "unletter", line_id: payable.id).sole.reason).to eq("wrong account")
    end

    it "leaves the open lines of the account as if the entry had never been booked: the payment alone, unallocated" do
      reverse(invoice_entry, confirm_unletter: true)
      open = Accounting::JournalEntryLine.where(account: account_440, lettering_id: nil).joins(:journal_entry)

      expect(open.sum("accounting_journal_entry_lines.credit - accounting_journal_entry_lines.debit")).to eq(-121)
    end

    # The reports count the entries "posted" only: the original, once reversed, drops out while its reversal stays, so a reversed entry
    # distorts the trial balance and R04. Not changed here (it moves ~20 report queries): see QUESTIONS.md, F07.
    it "keeps the aged balance equal to the account balance (I4) after the reversal" do
      pending "reports leave reversed originals out: QUESTIONS.md F07"
      account_440.update!(normal_balance: :credit)
      reverse(invoice_entry, confirm_unletter: true)

      aged = Accounting::AgedBalanceQuery.totals(Accounting::AgedBalanceQuery.new(kind: :supplier, as_of: fiscal_year.end_date).call).total

      expect(aged).to eq(-121)
    end

    it "also drops partial allocations of the lines" do
      Accounting::UnletterLines.call(lettering: payable.reload.lettering, reason: "redo", user: user)
      entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: today + 2, status: :draft)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      part = create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, debit: 60, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: account_570, debit: 0, credit: 60)
      Accounting::PostJournalEntry.call!(entry: entry)
      Accounting::AllocateLines.call(lines: [ payable.reload, part ])
      expect(Accounting::LineAllocation.touching([ payable.id ])).not_to be_empty

      result = reverse(invoice_entry.reload, confirm_unletter: true)

      expect(result).to be_success
      expect(Accounting::LineAllocation.touching([ payable.id ])).to be_empty
    end
  end

  describe "a scheduled reversal (auto_reverse_on)" do
    it "is generated as a draft by the job, once, and never posted by it" do
      entry = post_entry(auto_reverse_on: today + 30)

      travel_to(today + 29) { expect(Accounting::AutoReverseEntriesJob.perform_now).to eq(0) }
      travel_to(today + 30) do
        expect(Accounting::AutoReverseEntriesJob.perform_now).to eq(1)
        expect(Accounting::AutoReverseEntriesJob.perform_now).to eq(0)
      end

      reversal = entry.reload.reversal
      expect(reversal).to be_draft
      expect(reversal.entry_date).to eq(today + 30)
      expect(entry).to be_posted
    end

    it "flags the original as reversed, with the reason, when a person posts the draft" do
      entry = post_entry(auto_reverse_on: today + 30)
      travel_to(today + 30) { Accounting::AutoReverseEntriesJob.perform_now }

      Accounting::PostJournalEntry.call!(entry: entry.reload.reversal)

      expect(entry.reload).to be_reversed
      expect(Accounting::AuditLog.for_record(entry).for_action("reverse_entry").sole.reason).to include("Scheduled")
    end
  end
end
