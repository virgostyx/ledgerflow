require "rails_helper"

# Reads the fields an accountant would key in from the text of an invoice. Proposals only: each field keeps the
# line it came from, and the amounts are cross-checked.
RSpec.describe Accounting::DocumentFieldParser do
  include_context "with entity"

  let(:structured) { "+++#{Accounting::StructuredCommunication.for_id(123).then { |d| "#{d[0, 3]}/#{d[3, 4]}/#{d[7, 5]}" }}+++" }

  def parse(text) = described_class.call(text)
  def value(fields, name) = fields.dig(name, :value)

  describe "an English invoice" do
    let(:fields) do
      parse(<<~TEXT)
        ACME Consulting SPRL
        VAT BE0123456749
        Invoice No: INV-2026-0042
        Invoice date: 12/03/2026
        Due date: 11/04/2026
        Total excl. VAT 1.000,00 EUR
        VAT 21% 210,00 EUR
        Total incl. VAT 1.210,00 EUR
        Pay to IBAN BE68 5390 0754 7034
        Communication #{structured}
      TEXT
    end

    it "finds the number, the dates, the amounts, the IBAN, the VAT number and the communication" do
      expect(value(fields, :invoice_number)).to eq("INV-2026-0042")
      expect(value(fields, :invoice_date)).to eq("2026-03-12")
      expect(value(fields, :due_date)).to eq("2026-04-11")
      expect(value(fields, :subtotal)).to eq("1000.00")
      expect(value(fields, :vat_amount)).to eq("210.00")
      expect(value(fields, :total)).to eq("1210.00")
      expect(value(fields, :iban)).to eq("BE68539007547034")
      expect(value(fields, :supplier_vat)).to eq("BE0123456749")
      expect(value(fields, :structured_communication)).to eq(structured)
    end

    it "keeps, for each field, the line it came from" do
      expect(fields.dig(:invoice_number, :snippet)).to include("INV-2026-0042")
      expect(fields.dig(:total, :snippet)).to include("1.210,00")
      expect(fields.dig(:iban, :snippet)).to include("BE68 5390")
    end

    it "trusts amounts that add up (excl. + VAT = incl.)" do
      expect(fields.dig(:total, :confidence)).to eq(:high)
      expect(fields.dig(:subtotal, :confidence)).to eq(:high)
    end
  end

  describe "a French invoice" do
    let(:fields) do
      parse(<<~TEXT)
        Facture n° F-2026-77
        Date de facture : 5 mars 2026
        Échéance : 04/04/2026
        Total HTVA : 500,00 €
        TVA 21 % : 105,00 €
        Total TVAC : 605,00 €
      TEXT
    end

    it "reads the French labels, the spelled-out date and the amounts" do
      expect(value(fields, :invoice_number)).to eq("F-2026-77")
      expect(value(fields, :invoice_date)).to eq("2026-03-05")
      expect(value(fields, :due_date)).to eq("2026-04-04")
      expect(value(fields, :subtotal)).to eq("500.00")
      expect(value(fields, :vat_amount)).to eq("105.00")
      expect(value(fields, :total)).to eq("605.00")
    end
  end

  describe "a Dutch invoice" do
    let(:fields) do
      parse(<<~TEXT)
        Factuurnummer 2026/118
        Factuurdatum 05-03-2026
        Vervaldatum 5 april 2026
        Totaal excl. BTW 500,00
        BTW 105,00
        Totaal incl. BTW 605,00
      TEXT
    end

    it "reads the Dutch labels and month names" do
      expect(value(fields, :invoice_number)).to eq("2026/118")
      expect(value(fields, :invoice_date)).to eq("2026-03-05")
      expect(value(fields, :due_date)).to eq("2026-04-05")
      expect(value(fields, :total)).to eq("605.00")
    end
  end

  describe "amounts" do
    {
      "1.234,56"  => "1234.56", "1,234.56" => "1234.56", "1 234,56" => "1234.56", "1234.56" => "1234.56",
      "1234,5"    => "1234.50", "12,00"    => "12.00",   "0,99"     => "0.99",    "1.234.567,89" => "1234567.89"
    }.each do |written, expected|
      it "reads #{written} as #{expected}" do
        expect(value(parse("Total incl. VAT #{written} EUR"), :total)).to eq(expected)
      end
    end

    it "does not trust amounts that do not add up, and says so" do
      fields = parse("Total excl. VAT 100,00\nVAT 21,00\nTotal incl. VAT 130,00")

      expect(fields.dig(:total, :confidence)).to eq(:low)
    end

    it "proposes the total alone when it is the only amount, with less confidence" do
      fields = parse("Amount due: 250,00")

      expect(value(fields, :total)).to eq("250.00")
      expect(fields.dig(:total, :confidence)).to eq(:low)
    end
  end

  describe "numbers that look right but are not" do
    it "refuses an IBAN whose check digits are wrong" do
      expect(parse("IBAN BE68 5390 0754 7035")).not_to have_key(:iban)
    end

    it "refuses a Belgian VAT number whose check digits are wrong" do
      expect(parse("VAT BE0123456748")).not_to have_key(:supplier_vat)
    end

    it "refuses a structured communication whose check digits are wrong" do
      expect(parse("+++123/4567/89000+++")).not_to have_key(:structured_communication)
    end

    it "does not take a date for an invoice number" do
      expect(value(parse("Invoice date: 12/03/2026"), :invoice_number)).to be_nil
    end

    it "refuses an impossible date" do
      expect(parse("Invoice date: 31/02/2026")).not_to have_key(:invoice_date)
    end
  end

  describe "the supplier" do
    it "is the partner whose VAT number is on the invoice" do
      partner = create(:partner, :supplier, vat_number: "BE0123456749", name: "ACME Consulting")

      fields = parse("ACME CONSULTING SPRL\nVAT BE 0123.456.749")

      expect(value(fields, :supplier_partner_id)).to eq(partner.id)
      expect(value(fields, :supplier_name)).to eq("ACME Consulting")
      expect(value(fields, :supplier_vat)).to eq("BE0123456749")
    end

    it "is not guessed when no known partner has that number" do
      expect(parse("VAT BE0123456749")).not_to have_key(:supplier_partner_id)
    end

    it "does not match a partner of another entity" do
      ActsAsTenant.with_tenant(create(:entity)) { create(:partner, :supplier, vat_number: "BE0123456749") }

      expect(parse("VAT BE0123456749")).not_to have_key(:supplier_partner_id)
    end
  end

  describe "pages" do
    it "tells the page a field was read on (pages are separated by a form feed)" do
      fields = parse("Cover page\fInvoice No: A-1\nTotal incl. VAT 10,00\fterms")

      expect(fields.dig(:invoice_number, :page)).to eq(2)
      expect(fields.dig(:total, :page)).to eq(2)
    end
  end

  describe "when there is nothing to find" do
    it "returns nothing for blank text and for text without any of it" do
      expect(parse("")).to eq({})
      expect(parse(nil)).to eq({})
      expect(parse("Hello, this is a letter about the weather.")).to eq({})
    end
  end
end
