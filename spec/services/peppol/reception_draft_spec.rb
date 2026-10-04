require "rails_helper"

# F06 step 3: the draft supplier invoice of a received document: its lines (one per VAT category, charges and allowances in their category), the
# account proposed from the supplier's last invoice, else the suspense account, the VAT treatment from the entity's mapping, the supplier created
# "to validate", the payment reference kept, the credit note linked to its invoice.
RSpec.describe "The draft of a received invoice" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"
  include_context "with_suspense_account"

  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:user) { create(:user, role: :accountant) }

  def example(name) = Rails.root.join("spec/fixtures/files/peppol", name).read
  def take(xml, id = SecureRandom.hex(4)) = Peppol::ReceiveMessage.call(event: Peppol::Event.new(kind: :received, message_id: id, receiver: "0208:0999999999", xml: xml))[:message]

  describe "the lines" do
    it "has one line per VAT category and rate, the charge going to its category, on the suspense account" do
      invoice = take(example("base-example.xml")).invoice

      expect(invoice.lines.sole).to have_attributes(account_id: suspense_account.id, quantity: 1, unit_price: 1325, vat_rate: 25, subtotal_excl_vat: 1325, vat_amount: 331.25)
      expect(invoice.lines.sole.description).to include("item name").and include("Insurance")
    end

    it "keeps the totals of the document: those of its lines" do
      invoice = take(example("Allowance-example.xml")).invoice

      expect(invoice.lines.map { |l| [ l.vat_rate, l.subtotal_excl_vat ] }).to match_array([ [ 25, 4900 ], [ 0, 1000 ] ])
      expect(invoice).to have_attributes(subtotal_excl_vat: 5900, vat_amount: 1225, total_incl_vat: 7125, vat_treatment: "domestic")
    end

    it "puts the document allowance of a category against that category (the invoice lines cannot be negative)" do
      invoice = take(example("Vat-category-S.xml")).invoice

      expect(invoice.lines.map { |l| [ l.vat_rate, l.subtotal_excl_vat ] }).to match_array([ [ 25, 5000 ], [ 15, 2000 ] ])
    end

    it "makes a credit note of positive lines" do
      invoice = take(example("base-creditnote-correction.xml")).invoice

      expect(invoice).to be_credit_note
      expect(invoice.lines.sole.subtotal_excl_vat).to eq(1325)
    end

    it "waits for review when a category's lines add up to less than nothing" do
      xml = PeppolUbl.invoice(lines: [ [ 100, "S", 21 ], [ -150, "S", 21 ] ])

      expect(take(xml)).to have_attributes(status: "needs_review", invoice_id: nil)
    end

    it "has no line for a category that adds up to nothing" do
      xml = PeppolUbl.invoice(lines: [ [ 100, "S", 21 ], [ 0, "Z", 0 ] ])

      expect(take(xml).invoice.lines.count).to eq(1)
    end

    it "waits for review when the entity has no suspense account and the supplier has no default" do
      suspense_account.destroy!

      message = take(PeppolUbl.invoice)

      expect(message).to have_attributes(status: "needs_review")
      expect(message.problems.join).to include("suspense account")
    end
  end

  describe "the supplier" do
    it "is created as a supplier to validate, from the document, and the message says so" do
      message = take(example("base-example.xml"))

      partner = message.invoice.partner
      expect(partner).to have_attributes(name: "SupplierOfficialName Ltd", partner_type: "supplier", country: "GB", city: "London", to_validate: true)
      expect(message.note).to include("New supplier").and include("to validate")
    end

    it "is the one already known by its VAT number, left as it is" do
      known = create(:partner, partner_type: :supplier, name: "Known SA", vat_number: PeppolUbl::SUPPLIER_VAT)

      message = take(PeppolUbl.invoice)

      expect(message.invoice.partner).to eq(known)
      expect(known.reload.to_validate).to be(false)
      expect(message.note.to_s).not_to include("New supplier")
    end

    it "is found by its IBAN when the document has no VAT number, and waits when two partners share it" do
      create(:partner, partner_type: :supplier, name: "By IBAN", iban: "BE68539007547034")
      by_iban = take(PeppolUbl.invoice(vat: nil, iban: "BE68539007547034", number: "A-1"))
      expect(by_iban.invoice.partner.name).to eq("By IBAN")

      create(:partner, partner_type: :supplier, name: "Twin", iban: "FR1420041010050500013M02606")
      create(:partner, partner_type: :supplier, name: "Twin 2", iban: "FR1420041010050500013M02606")
      twins = take(PeppolUbl.invoice(vat: nil, iban: "FR1420041010050500013M02606", number: "A-2"))
      expect(twins).to have_attributes(status: "needs_review", invoice_id: nil)
    end
  end

  describe "the VAT treatment" do
    it "comes from the entity's mapping of the categories, ready for S, Z, E and O" do
      take(PeppolUbl.invoice)

      expect(Accounting::VatCategoryMapping.pluck(:category)).to match_array(%w[S Z E O])
      expect(Accounting::VatCategoryMapping.pluck(:vat_treatment).uniq).to eq([ "domestic" ])
    end

    it "uses what the entity changed, and leaves it as it is" do
      Accounting::VatCategoryMapping.create!(category: "E", vat_treatment: :exempt)

      invoice = take(PeppolUbl.invoice(lines: [ [ 100, "E", 0 ] ])).invoice

      expect(invoice.vat_treatment).to eq("exempt")
      expect(Accounting::VatCategoryMapping.find_by(category: "E").vat_treatment).to eq("exempt")
    end

    it "waits for the accountant when a category is not mapped, saying which" do
      message = take(PeppolUbl.invoice(lines: [ [ 100, "K", 0 ] ]))

      expect(message).to have_attributes(status: "needs_review")
      expect(message.problems.join).to include("K").and include("not mapped")
    end

    it "waits for review when the document mixes a reverse charge with ordinary VAT" do
      Accounting::VatCategoryMapping.create!(category: "AE", vat_treatment: :construction_reverse_charge, vat_rate: 21)

      message = take(PeppolUbl.invoice(lines: [ [ 100, "S", 21 ], [ 100, "AE", 0 ] ]))

      expect(message).to have_attributes(status: "needs_review", invoice_id: nil)
      expect(message.problems.join).to include("mixes")
    end
  end

  describe "the payment reference" do
    it "is kept on the invoice, as the supplier wrote it" do
      invoice = take(PeppolUbl.invoice(payment_id: "+++123/4567/89002+++")).invoice

      expect(invoice.payment_reference).to eq("+++123/4567/89002+++")
    end
  end

  describe "a credit note that names its invoice" do
    let!(:supplier) { create(:partner, partner_type: :supplier, name: "Fournisseur SA", vat_number: PeppolUbl::SUPPLIER_VAT) }
    let!(:original) do
      create(:invoice, :posted, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year, supplier_reference: "SUP-1", journal: purchase_journal)
    end

    def credit_note(reference) = PeppolUbl.invoice(root: "CreditNote", number: "CN-1", extra: "<cac:BillingReference><cac:InvoiceDocumentReference><cbc:ID>#{reference}</cbc:ID></cac:InvoiceDocumentReference></cac:BillingReference>")

    it "is linked to it when it is a posted invoice of the same supplier" do
      message = take(credit_note("SUP-1"))

      expect(message.invoice.credited_invoice).to eq(original)
      expect(message.note).to include("Credit note of invoice SUP-1")
    end

    it "is drafted all the same, and says so, when the invoice is not found" do
      message = take(credit_note("SUP-404"))

      expect(message).to have_attributes(status: "processed")
      expect(message.invoice.credited_invoice).to be_nil
      expect(message.note).to include("SUP-404")
    end
  end

  describe "coding and posting" do
    it "cannot be posted while its lines are on the suspense account" do
      invoice = take(PeppolUbl.invoice).invoice

      result = Accounting::PostInvoice.call(invoice: invoice)

      expect(result).to be_failure
      expect(result.message).to include("499000")
      expect(invoice.reload).to be_draft
    end

    it "is posted once coded, and the account is then proposed for the next invoice of that supplier" do
      invoice = take(PeppolUbl.invoice(number: "SUP-1")).invoice
      invoice.lines.each { |line| line.update!(account: account_604) }

      expect(Accounting::PostInvoice.call(invoice: invoice.reload)).to be_success

      defaults = Accounting::SupplierDefault.find_by!(partner_id: invoice.partner_id)
      expect(defaults).to have_attributes(account_id: account_604.id, vat_treatment: "domestic")

      second = take(PeppolUbl.invoice(number: "SUP-2")).invoice
      expect(second.lines.sole.account).to eq(account_604)
      expect(second.reload).to be_draft
    end

    it "does not remember a line that is still on the suspense account" do
      invoice = take(PeppolUbl.invoice).invoice
      invoice.lines.each { |line| line.update!(account: account_604) }
      Accounting::PostInvoice.call(invoice: invoice.reload)
      Accounting::SupplierDefault.delete_all
      invoice.lines.each { |line| line.update_columns(account_id: suspense_account.id) }

      Accounting::RememberSupplierDefaults.call(invoice: invoice.reload)

      expect(Accounting::SupplierDefault.count).to eq(0)
    end

    it "keeps the invoices typed by hand as they were: only a received one is held for coding" do
      typed = create(:invoice, :with_lines, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal)

      expect(Accounting::PostInvoice.call(invoice: typed)).to be_success
    end
  end
end
