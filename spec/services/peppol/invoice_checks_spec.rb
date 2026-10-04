require "rails_helper"

# F06 step 2: the automatic checks of a received invoice (docs/dev/features/spec.md §9): the lines add up to the total, the VAT recomputed by
# category within 0.01, a valid Belgian VAT number (modulo 97), a known currency, a coherent due date. A document that fails is not drafted.
RSpec.describe Peppol::InvoiceChecks do
  def example(name) = Rails.root.join("spec/fixtures/files/peppol", name).read
  def problems_of(xml) = described_class.call(Peppol::InvoiceMapper.call(xml))

  describe "the official examples" do
    %w[base-example.xml base-creditnote-correction.xml Allowance-example.xml Vat-category-S.xml vat-category-E.xml vat-category-Z.xml vat-category-O.xml sales-order-example.xml].each do |name|
      it "finds nothing wrong with #{name}" do
        expect(problems_of(example(name))).to eq([])
      end
    end

    it "flags the negative invoice, which is a credit note in disguise" do
      expect(problems_of(example("base-negative-inv-correction.xml")).join).to include("negative")
    end
  end

  describe "a valid invoice built for the specs" do
    it "has no problem, with a charge and two VAT rates" do
      xml = PeppolUbl.invoice(lines: [ [ 100, "S", 21 ], [ 50, "S", 6 ] ], charge: 10)

      expect(problems_of(xml)).to eq([])
    end
  end

  describe "the totals" do
    def tamper(xml, tag, from, to) = xml.sub(%r{(<cbc:#{tag}[^>]*>)#{Regexp.escape(from)}(</cbc:#{tag}>)}, "\\1#{to}\\2")

    it "refuses lines that do not add up to the total of the lines" do
      xml = tamper(PeppolUbl.invoice, "LineExtensionAmount", "100.00", "100.00").sub(%r{(<cac:LegalMonetaryTotal>\s*<cbc:LineExtensionAmount[^>]*>)100.00}, '\\1105.00')

      expect(problems_of(xml).join).to include("lines")
    end

    it "refuses a total without VAT that is not the lines plus charges less allowances" do
      xml = PeppolUbl.invoice(charge: 10).sub(%r{(<cbc:TaxExclusiveAmount[^>]*>)110.00}, '\\1111.00')

      expect(problems_of(xml).join).to include("TaxExclusiveAmount")
    end

    it "accepts a rounding difference of one cent on the VAT, not two" do
      one = tamper(PeppolUbl.invoice, "TaxAmount", "21.00", "21.01")
      two = tamper(PeppolUbl.invoice, "TaxAmount", "21.00", "21.02")

      expect(problems_of(one)).to eq([])
      expect(problems_of(two).join).to include("VAT")
    end

    it "refuses VAT that is not the rate applied to the taxable amount of its category" do
      xml = PeppolUbl.invoice(lines: [ [ 100, "S", 21 ] ]).gsub(%r{<cbc:Percent>21</cbc:Percent>}, "<cbc:Percent>6</cbc:Percent>")

      expect(problems_of(xml).join).to include("VAT")
    end

    it "refuses a total with VAT that is not the total without VAT plus the VAT" do
      xml = PeppolUbl.invoice.sub(%r{(<cbc:TaxInclusiveAmount[^>]*>)121.00}, '\\1130.00')

      expect(problems_of(xml).join).to include("TaxInclusiveAmount")
    end

    it "refuses a document with no line, and one without totals" do
      expect(problems_of("<Invoice><ID>X</ID><IssueDate>2026-09-01</IssueDate><DocumentCurrencyCode>EUR</DocumentCurrencyCode></Invoice>").join).to include("no invoice line").and include("totals")
    end
  end

  describe "the parties and the dates" do
    it "refuses a Belgian VAT number whose check digits are wrong, and accepts a right one" do
      expect(problems_of(PeppolUbl.invoice(vat: "BE0123456789")).join).to include("BE0123456789")
      expect(problems_of(PeppolUbl.invoice(vat: "BE0123456749"))).to eq([])
    end

    it "does not judge a VAT number of another country, nor the absence of one" do
      expect(problems_of(PeppolUbl.invoice(vat: "FR12345678901"))).to eq([])
      expect(problems_of(PeppolUbl.invoice(vat: nil))).to eq([])
    end

    it "refuses a currency that is not one of the supported ISO currencies" do
      expect(problems_of(PeppolUbl.invoice(currency: "XXX")).join).to include("XXX")
    end

    it "refuses a due date before the issue date, and has no opinion when there is none" do
      expect(problems_of(PeppolUbl.invoice(issue: "2026-09-10", due: "2026-09-01")).join).to include("due date")
      expect(problems_of(PeppolUbl.invoice(due: nil))).to eq([])
    end

    it "refuses a document with no number" do
      expect(problems_of(PeppolUbl.invoice(number: "")).join).to include("number")
    end
  end
end
