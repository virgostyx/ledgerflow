require "rails_helper"

RSpec.describe Peppol::ReceiveInvoice do
  include_context "with_open_fiscal_year"

  let(:partner) { create(:partner, :with_vat, partner_type: :supplier) }
  let(:sample_ubl) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
               xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
               xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:ID>FOURNISSEUR-2025-001</cbc:ID>
        <cbc:IssueDate>2025-06-01</cbc:IssueDate>
        <cbc:DueDate>2025-07-01</cbc:DueDate>
        <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
        <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
        <cac:AccountingSupplierParty>
          <cac:Party>
            <cac:PartyName><cbc:Name>Fournisseur SA</cbc:Name></cac:PartyName>
            <cac:PartyTaxScheme>
              <cbc:CompanyID>BE0123456789</cbc:CompanyID>
              <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>
            </cac:PartyTaxScheme>
          </cac:Party>
        </cac:AccountingSupplierParty>
        <cac:LegalMonetaryTotal>
          <cbc:TaxExclusiveAmount currencyID="EUR">500.00</cbc:TaxExclusiveAmount>
          <cbc:TaxInclusiveAmount currencyID="EUR">605.00</cbc:TaxInclusiveAmount>
          <cbc:PayableAmount currencyID="EUR">605.00</cbc:PayableAmount>
        </cac:LegalMonetaryTotal>
        <cac:TaxTotal>
          <cbc:TaxAmount currencyID="EUR">105.00</cbc:TaxAmount>
        </cac:TaxTotal>
      </Invoice>
    XML
  end

  context "avec un partenaire fournisseur existant (matching par TVA)" do
    it "crée une facture fournisseur" do
      expect {
        described_class.call(xml: sample_ubl, fiscal_year: fiscal_year)
      }.to change(Accounting::Invoice, :count).by(1)
    end

    it "retourne un contexte de succès" do
      result = described_class.call(xml: sample_ubl, fiscal_year: fiscal_year)
      expect(result).to be_success
    end

    it "crée la facture avec le bon numéro externe" do
      described_class.call(xml: sample_ubl, fiscal_year: fiscal_year)
      invoice = Accounting::Invoice.last
      expect(invoice.external_ref).to eq("FOURNISSEUR-2025-001")
    end

    it "crée la facture avec invoice_type supplier" do
      described_class.call(xml: sample_ubl, fiscal_year: fiscal_year)
      expect(Accounting::Invoice.last.invoice_type).to eq("supplier")
    end

    it "crée la facture avec le bon montant TVAC" do
      described_class.call(xml: sample_ubl, fiscal_year: fiscal_year)
      expect(Accounting::Invoice.last.total_incl_vat).to eq(BigDecimal("605.00"))
    end
  end

  context "avec un XML invalide" do
    it "retourne un contexte d'échec" do
      result = described_class.call(xml: "<invalid>", fiscal_year: fiscal_year)
      expect(result).to be_failure
    end
  end
end
