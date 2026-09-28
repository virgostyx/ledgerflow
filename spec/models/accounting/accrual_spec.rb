require "rails_helper"

RSpec.describe Accounting::Accrual, type: :model do
  include_context "with_open_fiscal_year"

  let!(:expense) { create(:account, code: "613000", label_fr: "Insurance", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:income)  { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:a490)    { create(:account, code: "490100", label_fr: "Deferred charges", account_class: 4, account_type: :asset, normal_balance: :debit) }
  let!(:a4902)   { create(:account, code: "490200", label_fr: "Accrued income", account_class: 4, account_type: :asset, normal_balance: :debit) }
  let!(:a492)    { create(:account, code: "492100", label_fr: "Accrued charges", account_class: 4, account_type: :liability, normal_balance: :credit) }
  let!(:a4922)   { create(:account, code: "492200", label_fr: "Deferred income", account_class: 4, account_type: :liability, normal_balance: :credit) }

  def accrual(type, total, from, to, **attrs)
    build(:accrual, accrual_type: type, total_amount: total, period_start: from, period_end: to, fiscal_year: fiscal_year, **attrs)
  end

  describe "#amount_at — table of cases" do
    [
      [ "annual insurance paid in October, deferred at 31 Dec", :deferred_charge, 1200, "2026-10-01", "2027-09-30", "2026-12-31", "897.53" ],
      [ "same over a leap year (366 days)",                       :deferred_charge, 1200, "2027-10-01", "2028-09-30", "2027-12-31", "898.36" ],
      [ "deferred income behaves the same way",                   :deferred_income, 600,  "2026-07-01", "2027-06-30", "2026-12-31", "297.53" ],
      [ "cut-off before the period: everything is unexpired",     :deferred_charge, 500,  "2027-01-01", "2027-12-31", "2026-12-31", "500.00" ],
      [ "cut-off after the period: nothing left to defer",        :deferred_charge, 500,  "2026-01-01", "2026-06-30", "2026-12-31", "0.00" ],
      [ "accrued charge: the elapsed share of the service",       :accrued_charge,  900,  "2026-11-01", "2027-01-31", "2026-12-31", "596.74" ],
      [ "accrued income: fully elapsed service = whole amount",   :accrued_income,  300,  "2026-11-01", "2026-12-15", "2026-12-31", "300.00" ],
      [ "accrued charge before the period starts: nothing yet",   :accrued_charge,  900,  "2027-02-01", "2027-03-31", "2026-12-31", "0.00" ]
    ].each do |name, type, total, from, to, cut_off, expected|
      it name do
        expect(accrual(type, total, Date.parse(from), Date.parse(to)).amount_at(Date.parse(cut_off))).to eq(BigDecimal(expected))
      end
    end
  end

  describe "validations and defaults" do
    it "is valid with a period, an amount and matching accounts" do
      expect(accrual(:deferred_charge, 100, Date.new(2026, 1, 1), Date.new(2026, 12, 31), pl_account: expense, accrual_account: a490)).to be_valid
    end

    it "rejects a period that ends before it starts and a non-positive amount" do
      expect(accrual(:deferred_charge, 100, Date.new(2026, 2, 1), Date.new(2026, 1, 1), pl_account: expense, accrual_account: a490)).not_to be_valid
      expect(accrual(:deferred_charge, 0, Date.new(2026, 1, 1), Date.new(2026, 2, 1), pl_account: expense, accrual_account: a490)).not_to be_valid
    end

    it "maps each type to the PCMN regularization account of the chart" do
      expect(described_class::ACCOUNT_CODES).to eq(deferred_charge: "490100", accrued_income: "490200", accrued_charge: "492100", deferred_income: "492200")
    end
  end
end
