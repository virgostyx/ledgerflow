require "rails_helper"

RSpec.describe "Booking accruals and their reversal", type: :service do
  include_context "with_open_fiscal_year"

  let!(:misc)    { create(:journal, journal_type: :misc) }
  let!(:expense) { create(:account, code: "613000", label_fr: "Insurance", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:income)  { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:a490)    { create(:account, code: "490100", label_fr: "Deferred charges", account_class: 4, account_type: :asset, normal_balance: :debit) }
  let!(:a492)    { create(:account, code: "492100", label_fr: "Accrued charges", account_class: 4, account_type: :liability, normal_balance: :credit) }
  let!(:a4922)   { create(:account, code: "492200", label_fr: "Deferred income", account_class: 4, account_type: :liability, normal_balance: :credit) }
  let(:cut_off)  { fiscal_year.end_date }

  # Covers Oct of the fiscal year to Sep of the next one: 92 elapsed days, 273 unexpired in a 365-day period.
  def accrual(type = :deferred_charge, **attrs)
    from = Date.new(fiscal_year.end_date.year, 10, 1)
    create(:accrual, accrual_type: type, fiscal_year: fiscal_year, period_start: from, period_end: from.advance(years: 1) - 1,
                     accrual_account: { deferred_charge: a490, accrued_charge: a492, deferred_income: a4922 }.fetch(type),
                     pl_account: type == :deferred_income ? income : expense, **attrs)
  end

  describe Accounting::BookAccrual do
    it "books a deferred charge as a balanced draft: debit 490, credit the charge account" do
      a = accrual
      result = described_class.call(accrual: a)
      expect(result).to be_success
      entry = a.reload.journal_entry
      expect(entry).to be_draft
      expect(entry).to have_attributes(entry_date: cut_off, journal: misc)
      expect(entry.lines.find_by(account: a490)).to have_attributes(debit: a.amount_at(cut_off), credit: 0)
      expect(entry.lines.find_by(account: expense)).to have_attributes(debit: 0, credit: a.amount_at(cut_off))
    end

    it "books an accrued charge the other way round (debit expense, credit 492)" do
      a = accrual(:accrued_charge, period_start: cut_off - 60, period_end: cut_off + 30)
      described_class.call(accrual: a)
      entry = a.reload.journal_entry
      expect(entry.lines.find_by(account: expense).debit).to be_positive
      expect(entry.lines.find_by(account: a492).credit).to be_positive
    end

    it "books deferred income as debit income, credit 492 deferred income" do
      a = accrual(:deferred_income)
      described_class.call(accrual: a)
      expect(a.reload.journal_entry.lines.find_by(account: income).debit).to eq(a.amount_at(cut_off))
    end

    it "refuses to book twice, or when there is nothing to book" do
      a = accrual
      described_class.call(accrual: a)
      expect(described_class.call(accrual: a.reload)).to be_failure
      nothing = accrual(period_start: cut_off - 100, period_end: cut_off - 10)
      expect(described_class.call(accrual: nothing)).to be_failure
    end
  end

  describe Accounting::ReverseAccrual do
    let(:next_year) do
      fiscal_year.update_columns(status: Accounting::FiscalYear.statuses[:pre_closing])
      create(:fiscal_year, year: fiscal_year.year + 1, start_date: fiscal_year.end_date + 1, end_date: fiscal_year.end_date + 365, status: :open)
    end

    it "generates the opposite entry as a draft on the first day of the next fiscal year" do
      next_year
      a = accrual
      Accounting::BookAccrual.call(accrual: a)
      result = described_class.call(accrual: a.reload)
      expect(result).to be_success
      rev = a.reload.reversal_entry
      expect(rev).to be_draft
      expect(rev).to have_attributes(entry_date: next_year.start_date, fiscal_year: next_year)
      expect(rev.lines.find_by(account: a490)).to have_attributes(debit: 0, credit: a.amount_at(cut_off))
      expect(rev.lines.find_by(account: expense)).to have_attributes(debit: a.amount_at(cut_off), credit: 0)
    end

    it "refuses an accrual that is not booked, or already reversed" do
      next_year
      a = accrual
      expect(described_class.call(accrual: a)).to be_failure
      Accounting::BookAccrual.call(accrual: a)
      described_class.call(accrual: a.reload)
      expect(described_class.call(accrual: a.reload)).to be_failure
    end

    it "refuses when the next fiscal year does not exist yet" do
      a = accrual
      Accounting::BookAccrual.call(accrual: a)
      expect(described_class.call(accrual: a.reload).message).to include("next fiscal year")
    end
  end
end
