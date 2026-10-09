require "rails_helper"

RSpec.describe Accounting::CashForecastQuery, type: :query do
  include_context "with_open_fiscal_year"

  let(:start)   { Date.current }
  let(:journal) { create(:journal, :purchase) }
  let!(:capital)   { create(:account, code: "100000", label_fr: "Capital", account_type: :equity, normal_balance: :credit, account_class: 1) }
  let!(:bank)      { create(:account, code: "550000", label_fr: "Bank", account_type: :asset, normal_balance: :debit, account_class: 5) }
  let!(:customers) { create(:account, code: "400000", label_fr: "Customers", account_type: :asset, normal_balance: :debit, account_class: 4, reconcilable: true) }
  let!(:suppliers) { create(:account, code: "440000", label_fr: "Suppliers", account_type: :liability, normal_balance: :credit, account_class: 4, reconcilable: true) }
  let!(:sales)     { create(:account, code: "700000", label_fr: "Sales", account_type: :revenue, normal_balance: :credit, account_class: 7) }
  let!(:expenses)  { create(:account, code: "600000", label_fr: "Purchases", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let(:partner_a)  { create(:partner, name: "A", payment_terms_days: 0) }
  let(:partner_b)  { create(:partner, name: "B", payment_terms_days: 15) }
  let(:supplier)   { create(:partner, :supplier, name: "S", payment_terms_days: 25) }

  def post(on, *lines)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: on)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each { |account, debit, credit, partner| create(:journal_entry_line, journal_entry: entry, account: account, debit: debit, credit: credit, partner: partner) }
    entry.post!
    entry
  end

  before do
    post(start - 60, [ bank, 5000, 0, nil ], [ capital, 0, 5000, nil ])
    post(start - 10, [ customers, 1000, 0, partner_a ], [ sales, 0, 1000, nil ])   # overdue receivable
    post(start - 5, [ customers, 600, 0, partner_b ], [ sales, 0, 600, nil ])      # due in +10 days: week 2
    post(start - 5, [ expenses, 400, 0, nil ], [ suppliers, 0, 400, supplier ])    # due in +20 days: week 3
    create(:cash_forecast_item, label: "Repair", direction: :outflow, amount: 250, recurrence: :once, first_date: start + 3)
  end

  def forecast(**opts) = described_class.new(start: start, **opts).call
  def closings(result) = result.weeks.first(4).map(&:closing)

  it "starts from the ledger cash (accounts 55/57) and builds 13 weekly columns" do
    result = forecast
    expect(result.weeks.size).to eq(13)
    expect(result.weeks.first.opening).to eq(5000)
    expect(result.weeks.first.from).to eq(start)
    expect(result.weeks.last.to).to eq(start + 13 * 7 - 1)
  end

  it "base: overdue receivables land in week 1, others at their due date, manual items in their week" do
    result = forecast(scenario: :base)
    expect(closings(result)).to eq([ 5750, 6350, 5950, 5950 ])
    expect(result.weeks.first.inflows).to eq(1000)
    expect(result.weeks.first.outflows).to eq(250)
    expect(result.weeks[0].opening).to eq(5000)
    expect(result.weeks[1].opening).to eq(result.weeks[0].closing)
  end

  it "chains balances: each week opens on the previous closing" do
    weeks = forecast.weeks
    weeks.each_cons(2) { |a, b| expect(b.opening).to eq(a.closing) }
    weeks.each { |w| expect(w.closing).to eq(w.opening + w.inflows - w.outflows) }
  end

  it "prudent: receipts slip by the client's observed delay plus N days" do
    result = forecast(scenario: :prudent, prudent_days: 10)
    expect(closings(result)).to eq([ 5750, 5750, 5950, 5950 ])
  end

  it "prudent: uses the client's observed payment delay from settled invoices" do
    invoice = create(:invoice, :posted, partner: partner_b, fiscal_year: fiscal_year, due_date: start - 40)
    invoiced = post(start - 45, [ customers, 500, 0, partner_b ], [ sales, 0, 500, nil ])
    invoiced.lines.find_by(account: customers).update_columns(invoice_id: invoice.id)
    paid = post(start - 30, [ bank, 500, 0, nil ], [ customers, 0, 500, partner_b ])
    Accounting::LineAllocation.create!(debit_line: invoiced.lines.find_by(account: customers), credit_line: paid.lines.find_by(account: customers),
                                       amount: 500, allocated_on: start - 30)

    weeks = forecast(scenario: :prudent, prudent_days: 10).weeks
    expect(weeks[4].inflows).to eq(600) # due +10, paid 10 days late historically, +10 prudent = +30 days = week 5
    expect(weeks[1].inflows).to eq(0)
  end

  it "optimistic: receipts arrive earlier than due" do
    result = forecast(scenario: :optimistic, early_days: 5)
    expect(result.weeks.first.inflows).to eq(1600)
  end

  it "receivable inflows equal the open customer balance of the aged balance (R04) when all fall in the horizon" do
    aged = Accounting::AgedBalanceQuery.totals(Accounting::AgedBalanceQuery.new(kind: :customer, as_of: start).call).total
    expect(forecast.weeks.sum { |w| w.sources.fetch(:receivables, 0) }).to eq(aged)
  end

  describe "approved and awaiting approval (B01a)" do
    # a supplier invoice with its open line on 440, due start + 3 days (week 1)
    def supplier_invoice(amount, status)
      invoice = create(:invoice, :posted, :supplier, partner: supplier, fiscal_year: fiscal_year, due_date: start + 3, payment_status: status)
      entry = post(start - 1, [ expenses, amount, 0, nil ], [ suppliers, 0, amount, supplier ])
      entry.lines.find_by(account: suppliers).update_columns(invoice_id: invoice.id, due_date: start + 3)
      invoice
    end

    def week_one_sources = forecast.weeks.first.sources

    it "tells what is approved (or needs no approval) from what still waits for approval, and from what is held" do
      supplier_invoice(100, :approved)
      supplier_invoice(10, :not_required)
      supplier_invoice(200, :to_approve)
      supplier_invoice(1000, :on_hold)
      supplier_invoice(2000, :disputed)

      sources = week_one_sources

      expect(sources[:payables]).to eq(110)
      expect(sources[:payables_pending]).to eq(200)
      expect(sources[:payables_held]).to eq(3000)
    end

    it "still counts every one of them as an outflow: waiting for approval is not a reason to forget a debt" do
      before = forecast.weeks.first.outflows
      supplier_invoice(100, :approved)
      supplier_invoice(200, :to_approve)
      supplier_invoice(1000, :on_hold)

      expect(forecast.weeks.first.outflows - before).to eq(1300)
    end

    it "counts a line that is not an invoice with the approved ones, as before" do
      expect(forecast.weeks[2].sources[:payables]).to eq(400)
      expect(forecast.weeks[2].sources).not_to include(:payables_pending)
    end

    it "makes the approved and the pending add up to the open supplier balance of the aged balance (R04)" do
      supplier_invoice(100, :approved)
      supplier_invoice(200, :to_approve)

      aged = Accounting::AgedBalanceQuery.totals(Accounting::AgedBalanceQuery.new(kind: :supplier, as_of: start).call).total
      total = forecast.weeks.sum { |w| w.sources.slice(:payables, :payables_pending, :payables_held).values.sum }

      expect(total).to eq(aged)
    end
  end

  it "adding a manual item changes only its own week" do
    before = forecast.weeks.map(&:closing)
    create(:cash_forecast_item, label: "Grant", direction: :inflow, amount: 100, recurrence: :once, first_date: start + 24)
    after = forecast.weeks.map(&:closing)
    expect(after.first(3)).to eq(before.first(3))
    expect(after[3..].zip(before[3..]).map { |a, b| a - b }).to all(eq(100))
  end

  it "flags weeks whose closing balance is under the threshold" do
    result = forecast(threshold: 6000)
    expect(result.weeks.map(&:alert).first(4)).to eq([ true, false, true, true ])
  end

  it "supports a 6-month horizon" do
    expect(forecast(horizon: :months_6).weeks.size).to eq(26)
  end

  it "estimates the VAT payable at its legal due date (20th of the following month)" do
    vat_payable    = create(:account, code: Accounting::AccountCodes::VAT_PAYABLE, label_fr: "VAT payable", account_type: :liability, normal_balance: :credit, account_class: 4)
    post(start - 5, [ bank, 210, 0, nil ], [ vat_payable, 0, 210, nil ])
    result = forecast
    vat_week = result.weeks.find { |w| w.sources.key?(:vat) }
    expect(vat_week.sources[:vat]).to eq(210)
    expect(vat_week.from).to be <= Date.new(start.year, start.month, 20).then { |d| d < start ? d.next_month : d }
  end
end
