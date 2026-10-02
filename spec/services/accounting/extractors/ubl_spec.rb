require "rails_helper"

RSpec.describe Accounting::Extractors::Ubl do
  include_context "with entity"

  let(:communication) { "+++#{Accounting::StructuredCommunication.for_id(77).then { |d| "#{d[0, 3]}/#{d[3, 4]}/#{d[7, 5]}" }}+++" }

  def fields(xml) = described_class.call(xml).fields
  def value(fields, name) = fields.dig(name, :value)

  it "reads the invoice straight from the XML, with no guessing" do
    result = described_class.call(sample_full_ubl(communication: communication))

    expect(result.method).to eq("ubl")
    expect(result.confidence).to eq(100)
    f = result.fields
    expect(value(f, :invoice_number)).to eq("UBL-2026-9")
    expect(value(f, :invoice_date)).to eq("2026-03-12")
    expect(value(f, :due_date)).to eq("2026-04-11")
    expect(value(f, :currency)).to eq("EUR")
    expect(value(f, :subtotal)).to eq("1000.00")
    expect(value(f, :vat_amount)).to eq("210.00")
    expect(value(f, :total)).to eq("1210.00")
    expect(value(f, :supplier_name)).to eq("ACME Consulting")
    expect(value(f, :supplier_vat)).to eq("BE0123456749")
    expect(value(f, :iban)).to eq("BE68539007547034")
    expect(value(f, :structured_communication)).to eq(communication)
    expect(value(f, :document_type)).to eq("invoice")
  end

  it "tells where each field was read in the document" do
    f = fields(sample_full_ubl)

    expect(f.dig(:invoice_number, :snippet)).to include("ID")
    expect(f.dig(:total, :snippet)).to include("TaxInclusiveAmount")
  end

  it "recognises a credit note" do
    expect(value(fields(sample_full_ubl(root: "CreditNote")), :document_type)).to eq("credit_note")
  end

  it "turns the document into text, so that it can be searched" do
    expect(described_class.call(sample_full_ubl).text).to include("UBL-2026-9", "ACME Consulting")
  end

  it "names the supplier a known partner when the VAT number matches" do
    partner = create(:partner, :supplier, vat_number: "BE0123456749")

    expect(value(fields(sample_full_ubl), :supplier_partner_id)).to eq(partner.id)
  end

  it "does not keep an IBAN or a VAT number whose check digits are wrong" do
    f = fields(sample_full_ubl(iban: "BE68539007547035", vat: "BE0123456748"))

    expect(f).not_to have_key(:iban)
    expect(f).not_to have_key(:supplier_vat)
  end

  it "refuses an XML that is not an invoice" do
    expect { described_class.call("<Order><ID>1</ID></Order>") }.to raise_error(Accounting::Extractors::Unreadable)
  end

  it "never resolves an entity, even when the XML declares one" do
    xxe = %(<?xml version="1.0"?><!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><Invoice><ID>&e;</ID></Invoice>)

    expect { described_class.call(xxe) }.to raise_error(Accounting::Extractors::Unreadable)
  end
end
