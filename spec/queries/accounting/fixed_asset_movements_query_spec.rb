require "rails_helper"

RSpec.describe Accounting::FixedAssetMovementsQuery, type: :query do
  include_context "with entity"

  let!(:fy2026) { create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :pre_closing) }
  let!(:fy2027) { create(:fiscal_year, year: 2027, start_date: Date.new(2027, 1, 1), end_date: Date.new(2027, 12, 31), status: :open) }
  let!(:misc)   { create(:journal, journal_type: :misc) }
  let!(:equipment) { create(:account, code: "240200", label_fr: "IT equipment", account_class: 2, account_type: :asset, normal_balance: :debit) }
  let!(:accumulated) { create(:account, code: "249000", label_fr: "Accumulated", account_class: 2, account_type: :asset, normal_balance: :credit) }
  let!(:expense) { create(:account, code: "630200", label_fr: "Depreciation", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:bank)    { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:loss)    { create(:account, code: "660100", label_fr: "Disposal loss", account_class: 6, account_type: :expense, normal_balance: :debit) }

  # 12 000 € / 5 years from Oct 2026 (600 in 2026, 2 400 in 2027) and 6 000 € / 5 years from Mar 2027 (1 000 in 2027).
  let!(:asset1) { create(:fixed_asset, :depreciable) }
  let!(:asset2) { create(:fixed_asset, :depreciable, description: "Second", acquisition_date: Date.new(2027, 3, 1), in_service_date: Date.new(2027, 3, 10), acquisition_value: "6000.00") }

  def post_cost(amount, on, fiscal_year)
    entry = create(:journal_entry, :draft, journal: misc, fiscal_year: fiscal_year, entry_date: on)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: equipment, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: bank, debit: 0, credit: amount)
    entry.post!
  end

  def movements(fiscal_year) = described_class.new(fiscal_year: fiscal_year).call
  def row(result, code = "24") = result.categories.find { |c| c.code == code }

  context "without disposal" do
    before do
      Accounting::PostDepreciation.call(fiscal_year: fy2026)
      Accounting::PostDepreciation.call(fiscal_year: fy2027)
    end

    it "A. acquisition value: begin, acquisitions, disposals, end" do
      r = row(movements(fy2027))
      expect([ r.cost_begin, r.acquisitions, r.disposals, r.cost_end ]).to eq([ 12_000, 6000, 0, 18_000 ])
    end

    it "B. depreciation: begin, booked, reversed, end" do
      r = row(movements(fy2027))
      expect([ r.dep_begin, r.dep_booked, r.dep_reversed, r.dep_end ]).to eq([ 600, 3400, 0, 4000 ])
    end

    it "C. net book value = A − B, and the first year starts from nothing" do
      expect(row(movements(fy2027)).net_value).to eq(14_000)
      first = row(movements(fy2026))
      expect([ first.cost_begin, first.acquisitions, first.dep_booked, first.net_value ]).to eq([ 0, 12_000, 600, 11_400 ])
    end

    it "totals across categories" do
      expect(movements(fy2027).totals.net_value).to eq(14_000)
    end
  end

  context "with a disposal in the year" do
    before do
      Accounting::PostDepreciation.call(fiscal_year: fy2026)
      asset1.update!(disposal_price: 9000)
      Accounting::DisposeFixedAsset.call(fixed_asset: asset1.reload, disposed_on: Date.new(2027, 6, 30))
      Accounting::PostDepreciation.call(fiscal_year: fy2027)
    end

    it "removes the disposed cost and its accumulated depreciation" do
      r = row(movements(fy2027))
      expect([ r.cost_begin, r.acquisitions, r.disposals, r.cost_end ]).to eq([ 12_000, 6000, 12_000, 6000 ])
      expect([ r.dep_begin, r.dep_booked, r.dep_reversed, r.dep_end ]).to eq([ 600, 2200, 1800, 1000 ])
      expect(r.net_value).to eq(5000)
    end

    it "computes the gain or loss on disposal: price − net book value at the disposal date" do
      disposal = movements(fy2027).disposals.sole
      expect(disposal).to have_attributes(cost: 12_000, accumulated: 1800, net_book_value: 10_200, price: 9000, gain_loss: -1200)
    end

    it "leaves the gain or loss empty when no price was recorded" do
      asset1.update_columns(disposal_price: nil)
      expect(movements(fy2027).disposals.sole.gain_loss).to be_nil
    end
  end

  describe "I10 checks against the ledger" do
    before do
      post_cost(12_000, Date.new(2026, 10, 1), fy2026)
      Accounting::PostDepreciation.call(fiscal_year: fy2026)
    end

    it "match when every posting comes from the register" do
      checks = movements(fy2026).checks
      expect(checks.map(&:difference)).to all(eq(0))
      expect(checks.size).to be >= 3
    end

    it "show an unregistered acquisition posted straight to the ledger" do
      post_cost(500, Date.new(2026, 11, 1), fy2026)
      check = movements(fy2026).checks.find { |c| c.label.include?("Acquisition") }
      expect(check.difference).to eq(500)
    end
  end
end
