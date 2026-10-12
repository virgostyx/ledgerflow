require "rails_helper"

# B01b: an IBAN received on an invoice is kept on the invoice and compared with the verified account of the supplier. It never changes the supplier's file:
# a different one only raises an alert and a task.
RSpec.describe Peppol::ReceiveInvoice, "the IBAN of the invoice" do
  include_context "with_open_fiscal_year"

  let(:partner) { create(:partner, :with_vat, partner_type: :supplier) }
  let(:owner)   { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:verified_iban) { "BE68539007547034" }

  def ubl(iban: "BE68 5390 0754 7034", number: "FOURNISSEUR-2025-001")
    payment = iban ? "<cac:PaymentMeans><cbc:PaymentMeansCode>30</cbc:PaymentMeansCode><cac:PayeeFinancialAccount><cbc:ID>#{iban}</cbc:ID></cac:PayeeFinancialAccount></cac:PaymentMeans>" : ""
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
               xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
               xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:ID>#{number}</cbc:ID>
        <cbc:IssueDate>2025-06-01</cbc:IssueDate>
        <cbc:DueDate>2025-07-01</cbc:DueDate>
        <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
        <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
        <cac:AccountingSupplierParty><cac:Party>
          <cac:PartyName><cbc:Name>Fournisseur SA</cbc:Name></cac:PartyName>
          <cac:PartyTaxScheme><cbc:CompanyID>BE0123456789</cbc:CompanyID><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme>
        </cac:Party></cac:AccountingSupplierParty>
        #{payment}
        <cac:LegalMonetaryTotal>
          <cbc:TaxExclusiveAmount currencyID="EUR">500.00</cbc:TaxExclusiveAmount>
          <cbc:TaxInclusiveAmount currencyID="EUR">605.00</cbc:TaxInclusiveAmount>
          <cbc:PayableAmount currencyID="EUR">605.00</cbc:PayableAmount>
        </cac:LegalMonetaryTotal>
        <cac:TaxTotal><cbc:TaxAmount currencyID="EUR">105.00</cbc:TaxAmount></cac:TaxTotal>
      </Invoice>
    XML
  end

  def receive(xml = ubl) = described_class.call(xml: xml, fiscal_year: fiscal_year, partner: partner)[:invoice]

  def verified_account!
    account = create(:partner_bank_account, :verified, partner: partner, iban: verified_iban, created_by: owner, verified_by: accountant)
    account
  end

  def told(user) = Accounting::Notification.where(user: user).pluck(:event)

  before { owner; accountant }

  it "keeps the IBAN written on the invoice, clean, and encrypted" do
    invoice = receive

    expect(invoice.reload.iban).to eq("BE68539007547034")
    stored = Accounting::Invoice.connection.select_value("SELECT iban FROM accounting_invoices WHERE id = #{invoice.id}")
    expect(stored).not_to include("5390")
  end

  it "keeps no IBAN that is not one, nor when the document has none" do
    expect(receive(ubl(iban: "BE00 0000 0000 0000", number: "A-1")).reload.iban).to be_nil
    expect(receive(ubl(iban: nil, number: "A-2")).reload.iban).to be_nil
  end

  context "when the supplier has a verified account" do
    before { verified_account! }

    it "says nothing when the invoice carries that account" do
      invoice = receive

      expect(Accounting::Task.about(invoice)).to be_empty
      expect(told(owner).grep(/mismatch/)).to be_empty
    end

    it "raises an alert for the owners and a task when the invoice carries another one, and changes nothing in the supplier's file" do
      before_iban = partner.iban
      invoice = receive(ubl(iban: "FR1420041010050500013M02606"))

      expect(told(owner).grep(/bank_account_invoice_mismatch/)).not_to be_empty
      task = Accounting::Task.about(invoice).sole
      expect(task).to have_attributes(kind: "to_check", priority: "high")
      expect(task.title).to include("IBAN")
      expect(task.description).to include("BE68 **** **** 7034", "FR14 **** **** **** **** ***2 606")
      expect(task.description + task.title).not_to include("FR1420041010050500013M02606")

      expect(partner.reload.iban).to eq(before_iban)
      expect(Accounting::PartnerBankAccount.count).to eq(1) # no account made from a document
      expect(Accounting::PartnerBankAccount.sole).to be_verified
    end

    it "raises it once when the same document comes twice" do
      xml = ubl(iban: "FR1420041010050500013M02606")
      receive(xml)
      receive(xml)

      expect(Accounting::Task.count).to eq(1)
      expect(told(owner).grep(/bank_account_invoice_mismatch/).size).to eq(1)
    end

    it "does nothing when the feature is off" do
      entity.update!(features: entity.features.merge("b01b" => false))

      invoice = receive(ubl(iban: "FR1420041010050500013M02606"))

      expect(Accounting::Task.about(invoice)).to be_empty
    end
  end

  it "has nothing to compare with when the supplier has no verified account, and makes no account itself" do
    invoice = receive

    expect(Accounting::Task.about(invoice)).to be_empty
    expect(Accounting::PartnerBankAccount.count).to eq(0)
  end
end
