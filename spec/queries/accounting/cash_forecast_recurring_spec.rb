require "rails_helper"

# F07: a recurring entry that feeds the cash forecast (R14) is read from the schedule, without typing it twice.
RSpec.describe Accounting::CashForecastQuery, "with recurring entries" do
  include_context "with_pcmn_accounts"

  let!(:fiscal_year) { create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2027, 12, 31), status: :open, entity: entity) }
  let!(:misc) { create(:journal, journal_type: :misc) }
  let(:start) { Date.new(2026, 11, 2) }
  let(:template) do
    Accounting::EntryTemplate.new(name: "Rent", journal: misc, description: "Rent").tap do |t|
      t.lines.build(account: account_604, side: :debit, amount_kind: :percent, percentage: 100, label: "Rent", position: 0)
      t.lines.build(account: account_440, side: :credit, amount_kind: :percent, percentage: 100, label: "Landlord", position: 1)
      t.save!
    end
  end

  def recurring(**attrs)
    Accounting::RecurringEntry.create!({ name: "Rent", entry_template: template, frequency: :monthly, day_of_month: 15, starts_on: Date.new(2026, 11, 1), base_amount: 800 }.merge(attrs))
  end

  def outflows = described_class.new(start: start).call.weeks.sum(&:outflows)

  it "counts the due dates of the horizon as outflows" do
    recurring(feeds_cash_forecast: true) # 15 Nov, 15 Dec, 15 Jan within 13 weeks from 2 Nov: until 1 Feb

    expect(outflows).to eq(3 * 800)
  end

  it "leaves out a recurring entry that does not feed it, or is paused" do
    recurring
    recurring(name: "Paused", feeds_cash_forecast: true).paused!

    expect(outflows).to eq(0)
  end

  it "counts revenue as an inflow" do
    account_440.update!(account_class: 4) # the factory gives every account class 6
    income = create(:account, code: "707000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit, entity: entity)
    t = Accounting::EntryTemplate.new(name: "Sub-let", journal: misc, description: "x").tap do |tpl|
      tpl.lines.build(account: account_440, side: :debit, amount_kind: :percent, percentage: 100, label: "a", position: 0)
      tpl.lines.build(account: income, side: :credit, amount_kind: :percent, percentage: 100, label: "b", position: 1)
      tpl.save!
    end
    recurring(entry_template: t, name: "Sub-let", feeds_cash_forecast: true, base_amount: 300)

    result = described_class.new(start: start).call

    expect(result.weeks.sum(&:inflows)).to eq(3 * 300)
  end
end
