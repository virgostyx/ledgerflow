require "rails_helper"

# F06 step 2, acceptance criteria 1 and 3 (docs/dev/features/spec.md §9): the official examples give drafts whose totals are those of the
# XML; an invoice whose totals are inconsistent waits for review, with the reason, and no draft.
RSpec.describe Peppol::ProcessMessage, "on the official examples" do
  include_context "with_open_fiscal_year"
  include_context "with_suspense_account"

  def example(name) = Rails.root.join("spec/fixtures/files/peppol", name).read
  def take(xml, id = SecureRandom.hex(4)) = Peppol::ReceiveMessage.call(event: Peppol::Event.new(kind: :received, message_id: id, receiver: "0208:0999999999", xml: xml))[:message]

  describe "in euros" do
    {
      "base-example.xml"             => [ 1325, 331.25, 1656.25, :invoice ],
      "sales-order-example.xml"      => [ 1325, 331.25, 1656.25, :invoice ],
      "Vat-category-S.xml"           => [ 7000, 1550, 8550, :invoice ],
      "Allowance-example.xml"        => [ 5900, 1225, 7125, :invoice ],
      "base-creditnote-correction.xml" => [ 1325, 331.25, 1656.25, :credit_note ]
    }.each do |name, (exclusive, vat, total, kind)|
      it "drafts #{name} with the totals of the XML" do
        message = take(example(name))

        expect(message).to have_attributes(status: "processed", problems: [])
        expect(message.invoice).to have_attributes(subtotal_excl_vat: exclusive, vat_amount: vat, total_incl_vat: total, currency: "EUR", status: "draft")
        expect(message.invoice.document_type).to eq(kind.to_s)
      end
    end

    it "waits for the accountant when the VAT category AE is not mapped (a reverse charge is a tax decision)" do
      message = take(example("constructed-reverse-charge-AE.xml"))

      expect(message).to have_attributes(status: "needs_review", invoice_id: nil)
      expect(message.problems.join).to include("AE").and include("not mapped")
    end

    it "drafts a reverse-charge invoice (category AE) once it is mapped: the total is the XML's, the VAT is self-assessed at the rate of the entity" do
      Accounting::VatCategoryMapping.create!(category: "AE", vat_treatment: :construction_reverse_charge, vat_rate: 21)

      message = take(example("constructed-reverse-charge-AE.xml"))

      expect(message).to have_attributes(status: "processed")
      expect(message.invoice).to have_attributes(vat_treatment: "construction_reverse_charge", subtotal_excl_vat: 1000, vat_amount: 210, total_incl_vat: 1000)
    end
  end

  describe "in another currency" do
    it "waits for review, saying that the rate is missing: a rate is never guessed" do
      message = take(example("vat-category-E.xml"))

      expect(message).to have_attributes(status: "needs_review", invoice_id: nil)
      expect(message.problems.join).to include("GBP").and include("exchange rate")
    end

    it "is drafted in its own currency, with the rate on file for the issue date" do
      Accounting::ExchangeRate.create!(currency: "GBP", rate_date: Date.new(2017, 1, 1), rate: BigDecimal("1.15"))
      Accounting::ExchangeRate.create!(currency: "SEK", rate_date: Date.new(2017, 1, 1), rate: BigDecimal("0.10"))

      gbp = take(example("vat-category-Z.xml"))
      sek = take(example("vat-category-O.xml"))

      expect(gbp.invoice).to have_attributes(currency: "GBP", exchange_rate: BigDecimal("1.15"), total_incl_vat: 1200, status: "draft")
      expect(sek.invoice).to have_attributes(currency: "SEK", exchange_rate: BigDecimal("0.10"), total_incl_vat: 3200)
    end
  end

  describe "a document that is not consistent (criterion 3)" do
    it "waits for review with the reason and makes no draft" do
      bad = example("base-example.xml").sub("<cbc:TaxInclusiveAmount currencyID=\"EUR\">1656.25", "<cbc:TaxInclusiveAmount currencyID=\"EUR\">1700.00")

      message = take(bad)

      expect(message).to have_attributes(status: "needs_review", invoice_id: nil)
      expect(message.problems.join).to include("TaxInclusiveAmount")
      expect(Accounting::Invoice.count).to eq(0)
    end

    it "waits for review for the negative invoice" do
      message = take(example("base-negative-inv-correction.xml"))

      expect(message).to have_attributes(status: "needs_review", invoice_id: nil)
      expect(message.problems.join).to include("negative")
    end

    it "lists every problem, not only the first" do
      bad = PeppolUbl.invoice(vat: "BE0123456789", currency: "XXX")

      expect(take(bad).problems.size).to be >= 2
    end

    it "can be worked on again once the cause is dealt with (the same message, a later try)" do
      message = take(example("vat-category-E.xml"))
      Accounting::ExchangeRate.create!(currency: "GBP", rate_date: Date.new(2017, 1, 1), rate: BigDecimal("1.15"))

      described_class.call(message: message)

      expect(message.reload).to have_attributes(status: "processed", problems: [])
      expect(message.invoice).to have_attributes(currency: "GBP")
    end
  end

  it "recognises a document it already has as a duplicate of the invoice, without a second draft" do
    first = take(PeppolUbl.invoice(number: "DUP-1"), "AP-1")
    second = take(PeppolUbl.invoice(number: "DUP-1"), "AP-2")

    expect(Accounting::Invoice.supplier.count).to eq(1)
    expect(second.invoice).to eq(first.invoice)
    expect(second.note).to include("already")
  end
end
