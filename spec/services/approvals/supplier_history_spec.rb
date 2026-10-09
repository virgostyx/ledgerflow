require "rails_helper"

# B01a §4.3: what an approver sees of the supplier, and the badge when the amount is more than twice their usual.
RSpec.describe Approvals::SupplierHistory do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:partner)     { create(:partner) }
  let(:account)     { create(:account) }

  def invoice_of(amount, status: :posted, partner: self.partner, date: Date.current, currency: "EUR", **attrs)
    create(:invoice, :supplier, partner: partner, fiscal_year: fiscal_year, status: status, invoice_date: date, currency: currency, **attrs).tap do |i|
      create(:invoice_line, invoice: i, account: account, unit_price: amount)
      i.update_columns(total_incl_vat: amount.to_d * 1.21, invoice_number: "ACH#{i.id}")
    end
  end

  let(:current) { invoice_of("1000.00", status: :draft) } # 1,210.00 incl. VAT

  it "lists the five latest posted invoices of the supplier, newest first, and their average" do
    6.times { |n| invoice_of("100.00", date: Date.current - (n + 1).days) }
    invoice_of("100.00", status: :cancelled)
    invoice_of("100.00", partner: create(:partner))

    history = described_class.for(current)

    expect(history.recent.size).to eq(5)
    expect(history.recent.map(&:invoice_date)).to eq(history.recent.map(&:invoice_date).sort.reverse)
    expect(history.average).to eq(BigDecimal("121.00"))
  end

  it "has no average without invoices" do
    history = described_class.for(current)

    expect(history.recent).to be_empty
    expect(history.average).to be_nil
    expect(history).not_to be_unusual_amount
  end

  it "flags an amount of more than twice the average, with at least three invoices behind it" do
    3.times { |n| invoice_of("100.00", date: Date.current - (n + 1).days) } # average 121.00, 2x = 242.00

    expect(described_class.for(current)).to be_unusual_amount
  end

  it "does not flag exactly twice the average" do
    3.times { |n| invoice_of("500.00", date: Date.current - (n + 1).days) } # average 605.00, 2x = 1,210.00

    expect(described_class.for(current)).not_to be_unusual_amount
  end

  it "does not flag with fewer than three invoices behind the average" do
    2.times { |n| invoice_of("100.00", date: Date.current - (n + 1).days) }

    expect(described_class.for(current)).not_to be_unusual_amount
  end

  it "only compares invoices in the same currency" do
    3.times { |n| invoice_of("100.00", date: Date.current - (n + 1).days, currency: "USD", exchange_rate: "1.1", exchange_rate_reason: "rate") }

    expect(described_class.for(current).recent).to be_empty
  end

  it "never counts the invoice itself" do
    3.times { |n| invoice_of("100.00", date: Date.current - (n + 1).days) }
    own = invoice_of("1000.00")

    expect(described_class.for(own).recent).not_to include(own)
  end

  it "names its warnings, which is what keeps an invoice out of a bulk approval" do
    3.times { |n| invoice_of("100.00", date: Date.current - (n + 1).days) }

    expect(described_class.for(current).warnings).to eq([ :unusual_amount ])
  end
end
