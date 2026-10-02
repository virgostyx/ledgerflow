require "rails_helper"

# "Create the entry" from a document: a prefilled DRAFT supplier invoice, linked to the document. Nothing is posted,
# and no line is invented: the accountant adds the lines and their accounts.
RSpec.describe Accounting::CreateInvoiceFromDocument do
  include_context "with_open_fiscal_year"

  let(:user)     { create(:user) }
  let!(:journal) { create(:journal, :purchase) }
  let(:partner)  { create(:partner, :supplier, vat_number: "BE0123456749") }
  let(:invoice_text) do
    "ACME Consulting SPRL\nVAT BE0123456749\nInvoice No: INV-2026-0042\nInvoice date: #{Date.current.strftime('%d/%m/%Y')}\nDue date: #{(Date.current + 30).strftime('%d/%m/%Y')}\n" \
      "Total excl. VAT 1.000,00 EUR\nVAT 21% 210,00 EUR\nTotal incl. VAT 1.210,00 EUR"
  end
  let(:document) do
    content = Prawn::Document.new { |pdf| invoice_text.each_line { |line| pdf.text line.chomp } }.render
    Accounting::UploadDocument.call(io: StringIO.new(content), filename: "acme.pdf", user: user)[:document].tap { |doc| Accounting::ExtractDocument.call(document: doc) }
  end

  def create_draft(**options) = described_class.call(document: document, partner: partner, user: user, **options)

  describe "the draft" do
    let(:invoice) { create_draft[:invoice] }

    it "is a supplier invoice in draft, for the chosen supplier, with the header read from the document" do
      expect(invoice).to be_persisted
      expect(invoice).to have_attributes(status: "draft", invoice_type: "supplier", document_type: "invoice", partner: partner, journal: journal,
                                         invoice_date: Date.current, due_date: Date.current + 30, supplier_reference: "INV-2026-0042", currency: "EUR")
      expect(invoice).to have_attributes(subtotal_excl_vat: BigDecimal("1000"), vat_amount: BigDecimal("210"), total_incl_vat: BigDecimal("1210"))
      expect(invoice.fiscal_year).to eq(fiscal_year)
    end

    it "has no line: the accountant adds them, with their accounts" do
      expect(invoice.lines).to be_empty
    end

    it "posts nothing" do
      expect { invoice }.not_to change(Accounting::JournalEntry, :count)
      expect(invoice.journal_entry).to be_nil
    end

    it "is linked to the document, which leaves the inbox and is classified as a purchase invoice" do
      invoice

      expect(document.reload.links.sole.target).to eq(invoice)
      expect(document).to be_linked
      expect(document).to be_purchase_invoice
    end

    it "is audited, with where the values came from" do
      invoice

      row = Accounting::AuditLog.where(action: "document_invoice_draft", auditable_id: document.id).sole
      expect(row.payload).to include("invoice_id" => invoice.id, "partner_id" => partner.id)
      expect(row.payload["unconfirmed_fields"]).to include("invoice_number", "total")
    end
  end

  describe "what a person confirmed" do
    it "wins over what was proposed, and is not listed as unconfirmed" do
      Accounting::ConfirmDocumentField.call(document: document, field: "invoice_number", value: "INV-CORRECTED", user: user)
      Accounting::ConfirmDocumentField.call(document: document, field: "total", value: "1.300,00", user: user)

      invoice = create_draft[:invoice]

      expect(invoice.supplier_reference).to eq("INV-CORRECTED")
      expect(invoice.total_incl_vat).to eq(BigDecimal("1300"))
      expect(Accounting::AuditLog.find_by(action: "document_invoice_draft").payload["unconfirmed_fields"]).not_to include("invoice_number", "total")
    end
  end

  describe "when the document is a credit note" do
    it "makes a credit note" do
      Accounting::ExtractDocument.call(document: document)
      data = document.reload.extracted_data
      data["extraction"]["fields"]["document_type"] = { "value" => "credit_note", "snippet" => "/CreditNote", "page" => nil, "confidence" => "high", "confirmed" => false }
      document.update_columns(extracted_data: data)

      expect(create_draft[:invoice]).to be_credit_note
    end
  end

  describe "what is missing" do
    it "takes today when the document has no readable date" do
      document # extraction done
      data = document.extracted_data
      data["extraction"]["fields"].delete("invoice_date")
      document.update_columns(extracted_data: data)

      expect(create_draft[:invoice].invoice_date).to eq(Date.current)
    end

    it "falls back to EUR for a currency that is not supported" do
      data = document.extracted_data
      data["extraction"]["fields"]["currency"] = { "value" => "ZZZ", "snippet" => nil, "page" => nil, "confidence" => "high", "confirmed" => false }
      document.update_columns(extracted_data: data)

      expect(create_draft[:invoice].currency).to eq("EUR")
    end

    it "makes a draft with only the supplier when nothing could be read" do
      blank = Accounting::UploadDocument.call(io: StringIO.new(sample_csv), filename: "x.csv", user: user)[:document]

      invoice = described_class.call(document: blank, partner: partner, user: user)[:invoice]

      expect(invoice).to be_draft
      expect(invoice.supplier_reference).to be_nil
    end
  end

  describe "refusals" do
    it "needs a supplier of this entity" do
      customer = create(:partner, :customer)
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:partner, :supplier) }

      expect(create_draft(partner: customer)).to be_failure
      expect(create_draft(partner: foreign)).to be_failure
      expect(create_draft(partner: nil)).to be_failure
      expect(Accounting::Invoice.count).to eq(0)
    end

    it "needs an open fiscal year that covers the date" do
      fiscal_year.update!(status: :closed)

      result = create_draft

      expect(result).to be_failure
      expect(result.message).to match(/fiscal year/i)
      expect(document.reload.links).to be_empty
    end

    it "does not touch an archived document" do
      document.update!(status: :archived)

      expect(create_draft).to be_failure
    end
  end

  describe "a probable duplicate (same supplier, same invoice number)" do
    let!(:existing) { create(:invoice, :supplier, partner: partner, supplier_reference: "INV-2026-0042", fiscal_year: fiscal_year, journal: journal) }

    it "is refused, naming the invoice already there" do
      result = create_draft

      expect(result).to be_failure
      expect(result[:reason]).to eq(:duplicate_invoice)
      expect(result[:existing]).to eq(existing)
      expect(Accounting::Invoice.count).to eq(1)
      expect(document.reload.links).to be_empty
    end

    it "goes through with a reason, which is audited" do
      result = create_draft(override_reason: "Supplier re-issued the invoice after a credit note")

      expect(result).to be_success
      row = Accounting::AuditLog.find_by(action: "document_duplicate_override")
      expect(row.reason).to eq("Supplier re-issued the invoice after a credit note")
      expect(row.payload).to include("existing_invoice_id" => existing.id)
    end

    it "is not one when the invoice already there was cancelled" do
      existing.update_columns(status: Accounting::Invoice.statuses[:cancelled])

      expect(create_draft).to be_success
    end

    it "is not one for another supplier" do
      other = create(:partner, :supplier)

      expect(create_draft(partner: other)).to be_success
    end
  end

  describe "a document frozen by a validated entry" do
    it "can still lead to a draft, its kind staying as it was" do
      Accounting::LinkDocument.call(document: document, target: create(:journal_entry, :posted, fiscal_year: fiscal_year), user: user)

      result = create_draft

      expect(result).to be_success
      expect(document.reload).to be_other
    end
  end
end
