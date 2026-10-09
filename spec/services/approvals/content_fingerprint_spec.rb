require "rails_helper"

# B01a §4.5: an approval holds for one content. What changes the fingerprint invalidates it; a free label does not.
RSpec.describe Approvals::ContentFingerprint do
  include_context "with entity"

  let(:account) { create(:account) }
  let(:invoice) do
    create(:invoice, :supplier, due_date: Date.new(2026, 11, 15)).tap do |i|
      create(:invoice_line, invoice: i, account: account, description: "Consulting", quantity: 2, unit_price: "500.00", vat_rate: "21.00")
    end
  end

  def fingerprint(record = invoice) = described_class.call(record.reload)

  it "is a SHA-256" do
    expect(fingerprint).to match(/\A\h{64}\z/)
  end

  it "is the same twice for the same content" do
    expect(fingerprint).to eq(fingerprint)
  end

  {
    "the supplier"   => proc { |i| i.update!(partner: create(:partner)) },
    "the amount"     => proc { |i| i.lines.first.update!(unit_price: "600.00") },
    "the quantity"   => proc { |i| i.lines.first.update!(quantity: 3) },
    "the VAT rate"   => proc { |i| i.lines.first.update!(vat_rate: "6.00") },
    "the account"    => proc { |i| i.lines.first.update!(account: create(:account)) },
    "a new line"     => proc { |i| create(:invoice_line, invoice: i, account: i.lines.first.account, unit_price: "10.00") },
    "the due date"   => proc { |i| i.update!(due_date: Date.new(2026, 12, 1)) },
    "the currency"   => proc { |i| i.update!(currency: "USD", exchange_rate: "1.1") },
    "the document"   => proc { |i| create(:document).tap { |d| Accounting::DocumentLink.create!(document: d, target: i) } }
  }.each do |what, change|
    it "changes with #{what}" do
      before = fingerprint
      instance_exec(invoice, &change)

      expect(fingerprint).not_to eq(before)
    end
  end

  {
    "the free description" => proc { |i| i.update!(description: "Reworded") },
    "the notes"            => proc { |i| i.update!(notes: "Called the supplier") },
    "a line's label"       => proc { |i| i.lines.first.update!(description: "Consulting, October") }
  }.each do |what, change|
    it "does not change with #{what}" do
      before = fingerprint
      instance_exec(invoice, &change)

      expect(fingerprint).to eq(before)
    end
  end

  it "does not change when the invoice is posted and numbered" do
    before = fingerprint
    invoice.update_columns(invoice_number: "ACH2026/0001", status: Accounting::Invoice.statuses[:posted])

    expect(fingerprint).to eq(before)
  end

  it "does not depend on the order lines were typed in" do
    other = create(:invoice, :supplier, due_date: invoice.due_date, partner: invoice.partner, fiscal_year: invoice.fiscal_year)
    create(:invoice_line, invoice: other, account: account, description: "B", quantity: 1, unit_price: "10.00", vat_rate: "21.00", position: 2)
    create(:invoice_line, invoice: other, account: account, description: "A", quantity: 1, unit_price: "20.00", vat_rate: "21.00", position: 1)
    swapped = create(:invoice, :supplier, due_date: invoice.due_date, partner: invoice.partner, fiscal_year: invoice.fiscal_year)
    create(:invoice_line, invoice: swapped, account: account, description: "A", quantity: 1, unit_price: "20.00", vat_rate: "21.00", position: 2)
    create(:invoice_line, invoice: swapped, account: account, description: "B", quantity: 1, unit_price: "10.00", vat_rate: "21.00", position: 1)

    expect(fingerprint(other)).to eq(fingerprint(swapped))
  end
end
