require "rails_helper"

# F06 step 2: the UBL of Peppol BIS Billing 3.0 read into a canonical invoice. Tried on the official examples of OpenPeppol
# (spec/fixtures/files/peppol/README.md), whose shapes the first reader did not foresee (several tax totals, negative lines, no VAT number).
RSpec.describe Peppol::InvoiceMapper do
  def example(name) = Rails.root.join("spec/fixtures/files/peppol", name).read
  def map(name) = described_class.call(example(name))

  describe "the base example" do
    subject(:invoice) { map("base-example.xml") }

    it "reads the header" do
      expect(invoice).to have_attributes(kind: :invoice, number: "Snippet1", issue_date: Date.new(2017, 11, 13), due_date: Date.new(2017, 12, 1), currency: "EUR")
      expect(invoice.references).to include(buyer: "0150abc")
    end

    it "reads the supplier: names, VAT, endpoint, IBAN, address and country" do
      expect(invoice.supplier).to have_attributes(name: "SupplierOfficialName Ltd", trade_name: "SupplierTradingName Ltd.", vat: "GB1232434",
                                                  endpoint: "0088:9482348239847239874", iban: "IBAN32423940", city: "London", country: "GB", street: "Main street 1", zip: "GB 123 EW")
    end

    it "reads the lines, with a negative one" do
      expect(invoice.lines.map { |l| [ l.id, l.quantity, l.unit_price, l.amount, l.tax_category, l.tax_percent ] }).to eq(
        [ [ "1", 7, 400, 2800, "S", 25 ], [ "2", -3, 500, -1500, "S", 25 ] ]
      )
      expect(invoice.lines.first).to have_attributes(name: "item name", description: "Description of item", unit: "DAY")
    end

    it "reads the document charge, the tax subtotals and the totals" do
      expect(invoice.charges.map { |c| [ c.charge, c.amount, c.reason, c.tax_category, c.tax_percent ] }).to eq([ [ true, 25, "Insurance", "S", 25 ] ])
      expect(invoice.tax_subtotals.map { |s| [ s.category, s.percent, s.taxable, s.tax ] }).to eq([ [ "S", 25, 1325, 331.25 ] ])
      expect(invoice.totals).to have_attributes(lines: 1300, tax_exclusive: 1325, tax_inclusive: 1656.25, charge: 25, payable: 1656.25)
      expect(invoice.tax_total).to eq(BigDecimal("331.25"))
    end

    it "reads the payment: means, communication, and the amounts as BigDecimal" do
      expect(invoice.payment).to include(means: "30", id: "Snippet1")
      expect(invoice.totals.payable).to be_a(BigDecimal)
    end
  end

  it "reads a credit note, with its own line elements" do
    credit = map("base-creditnote-correction.xml")

    expect(credit).to have_attributes(kind: :credit_note, number: "Snippet1")
    expect(credit.lines.map(&:amount)).to eq([ 2800, -1500 ])
    expect(credit.lines.first.quantity).to eq(7)
  end

  it "takes the tax total that is in the currency of the document when there are two (the other is the tax currency)" do
    invoice = map("Allowance-example.xml")

    expect(invoice).to have_attributes(currency: "EUR", tax_currency: "SEK")
    expect(invoice.tax_total).to eq(BigDecimal("1225"))
    expect(invoice.tax_subtotals.map(&:category)).to eq(%w[S E])
    expect(invoice.charges.map { |c| [ c.charge, c.amount ] }).to eq([ [ true, 200 ], [ false, 200 ] ])
    expect(invoice.totals).to have_attributes(allowance: 200, charge: 200, prepaid: 1000, payable: 6125)
  end

  it "reads the document without any VAT number or VAT category other than the standard one" do
    invoice = map("vat-category-O.xml")

    expect(invoice).to have_attributes(currency: "SEK")
    expect(invoice.supplier.vat).to be_nil
    expect(invoice.lines.sole).to have_attributes(tax_category: "O", tax_percent: 0)
  end

  it "reads the other official examples" do
    %w[Vat-category-S.xml vat-category-E.xml vat-category-Z.xml sales-order-example.xml base-negative-inv-correction.xml].each do |name|
      expect(map(name)).to have_attributes(number: be_present, currency: be_present, totals: have_attributes(tax_exclusive: be_a(BigDecimal)))
    end
  end

  describe "what it refuses" do
    it "does not read what is not XML" do
      expect { described_class.call("not xml") }.to raise_error(Peppol::InvoiceMapper::Unreadable)
    end

    it "does not read a document that is neither an invoice nor a credit note" do
      expect { described_class.call("<Order xmlns='urn:oasis:names:specification:ubl:schema:xsd:Order-2'/>") }.to raise_error(Peppol::InvoiceMapper::Unreadable, /Order/)
    end

    it "is tolerant of what is missing: it reads what is there, the checks say what is wrong" do
      invoice = described_class.call("<Invoice><ID>X</ID></Invoice>")

      expect(invoice.number).to eq("X")
      expect(invoice.lines).to eq([])
      expect(invoice.totals.tax_exclusive).to be_nil
    end
  end
end
