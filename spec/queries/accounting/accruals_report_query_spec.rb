require "rails_helper"

RSpec.describe Accounting::AccrualsReportQuery, type: :query, bullet_strict: true do
  include_context "with_open_fiscal_year"

  let!(:misc)    { create(:journal, journal_type: :misc) }
  let!(:expense) { create(:account, code: "613000", label_fr: "Insurance", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:a490)    { create(:account, code: "490100", label_fr: "Deferred charges", account_class: 4, account_type: :asset, normal_balance: :debit) }
  let!(:a4902)   { create(:account, code: "490200", label_fr: "Accrued income", account_class: 4, account_type: :asset, normal_balance: :debit) }
  let!(:a492)    { create(:account, code: "492100", label_fr: "Accrued charges", account_class: 4, account_type: :liability, normal_balance: :credit) }
  let!(:a4922)   { create(:account, code: "492200", label_fr: "Deferred income", account_class: 4, account_type: :liability, normal_balance: :credit) }
  let(:cut_off)  { fiscal_year.end_date }
  let(:report)   { described_class.new(fiscal_year: fiscal_year).call }

  def book(accrual, post: true)
    Accounting::BookAccrual.call(accrual: accrual)
    accrual.reload.journal_entry.post! if post
    accrual
  end

  def deferral(**attrs)
    from = Date.new(cut_off.year, 10, 1)
    create(:accrual, fiscal_year: fiscal_year, period_start: from, period_end: from.advance(years: 1) - 1, **attrs)
  end

  describe "rows and I11 checks" do
    it "matches the ledger once the regularization is validated" do
      book(deferral)
      check = report.checks.find { |c| c.label.include?("490100") }
      expect(check.register).to eq(deferral_amount = report.rows.sole.amount)
      expect(check.difference).to eq(0)
      expect(deferral_amount).to be_positive
    end

    it "flags a difference when the balance moved outside the regularizations" do
      book(deferral)
      entry = create(:journal_entry, :draft, journal: misc, fiscal_year: fiscal_year, entry_date: cut_off)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: a490, debit: 50, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: expense, debit: 0, credit: 50)
      entry.post!
      expect(report.checks.find { |c| c.label.include?("490100") }.difference).to eq(50)
    end

    it "leaves an unbooked or draft regularization out of the register and flags it" do
      deferral
      draft = book(deferral(description: "Second"), post: false)
      expect(report.checks.find { |c| c.label.include?("490100") }.register).to eq(0)
      expect(report.rows.map(&:status)).to contain_exactly(:pending, :draft)
      expect(report.rows.find { |r| r.accrual == draft }.status).to eq(:draft)
    end

    it "signals a booked regularization that has no reversal" do
      a = book(deferral)
      expect(report.rows.sole.missing_reversal).to be(true)
      next_year = create(:fiscal_year, year: fiscal_year.year + 1, start_date: cut_off + 1, end_date: cut_off + 365, status: :pre_closing)
      Accounting::ReverseAccrual.call(accrual: a.reload)
      expect(described_class.new(fiscal_year: fiscal_year).call.rows.sole.missing_reversal).to be(false)
      expect(next_year).to be_present
    end
  end

  describe "cut-off lists" do
    let(:supplier) { create(:partner, :supplier, name: "Late Supplier") }
    let(:other)    { create(:partner, name: "Ordinary") }

    def invoice(partner:, type:, date:, created: nil, service: nil)
      inv = create(:invoice, :posted, partner: partner, invoice_type: type, invoice_date: date, fiscal_year: fiscal_year)
      create(:invoice_line, invoice: inv, service_start: service&.first, service_end: service&.last)
      inv.update_columns(created_at: created) if created
      inv
    end

    it "list 1: documents dated up to the closing but recorded in the 30 days after it — and nothing else" do
      late   = invoice(partner: supplier, type: :supplier, date: cut_off - 5, created: (cut_off + 10).to_time)
      _early = invoice(partner: other, type: :supplier, date: cut_off - 5, created: (cut_off - 2).to_time)
      _far   = invoice(partner: other, type: :supplier, date: cut_off - 5, created: (cut_off + 45).to_time)
      expect(report.recorded_after_closing.map(&:invoice)).to eq([ late ])
    end

    it "list 1 also takes invoices dated after the closing for a service ended before it" do
      after = invoice(partner: supplier, type: :supplier, date: cut_off + 3, created: (cut_off + 3).to_time, service: [ cut_off - 30, cut_off - 1 ])
      expect(report.recorded_after_closing.map(&:invoice)).to eq([ after ])
    end

    it "list 2: invoices of the year whose service period runs into the next year — and nothing else" do
      overflow = invoice(partner: supplier, type: :supplier, date: cut_off - 60, service: [ cut_off - 60, cut_off + 200 ])
      _inside  = invoice(partner: other, type: :supplier, date: cut_off - 60, service: [ cut_off - 60, cut_off - 1 ])
      _nodates = invoice(partner: other, type: :supplier, date: cut_off - 60)
      expect(report.spanning_next_year.map(&:invoice)).to eq([ overflow ])
    end
  end
end
