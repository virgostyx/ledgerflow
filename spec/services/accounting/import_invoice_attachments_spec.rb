require "rails_helper"

# F03: the UBL and PDF already kept on invoices (Peppol, BudgetFlow) join the document store, once.
RSpec.describe Accounting::ImportInvoiceAttachments do
  include_context "with entity"

  let(:invoice) { create(:invoice, :draft, invoice_type: :supplier, partner: create(:partner, :supplier)) }

  def attach(invoice, name, content, type)
    invoice.public_send(name).attach(io: StringIO.new(content), filename: "#{name}.#{type == 'application/pdf' ? 'pdf' : 'xml'}", content_type: type)
  end

  it "stores each attachment as a document that came from Peppol, linked to its invoice" do
    attach(invoice, :pdf_document, sample_pdf("peppol"), "application/pdf")
    attach(invoice, :ubl_document, sample_ubl, "application/xml")

    result = described_class.call

    expect(result[:imported]).to eq(2)
    documents = Accounting::Document.order(:id)
    expect(documents.map(&:origin).uniq).to eq([ "peppol" ])
    expect(documents.flat_map { |d| d.links.map(&:target) }).to all(eq(invoice))
    expect(documents.map(&:status).uniq).to eq([ "linked" ])
  end

  it "is idempotent: a second run imports nothing" do
    attach(invoice, :pdf_document, sample_pdf("peppol"), "application/pdf")
    described_class.call

    expect(described_class.call[:imported]).to eq(0)
    expect(Accounting::Document.count).to eq(1)
  end

  it "links an already stored identical file to the invoice instead of storing it twice" do
    content = sample_pdf("known")
    Accounting::UploadDocument.call(io: StringIO.new(content), filename: "known.pdf", user: nil)
    attach(invoice, :pdf_document, content, "application/pdf")

    described_class.call

    expect(Accounting::Document.count).to eq(1)
    expect(Accounting::Document.sole.links.map(&:target)).to eq([ invoice ])
  end

  it "reports a file the store refuses and carries on" do
    attach(invoice, :ubl_document, "not xml at all <", "application/xml")
    other = create(:invoice, :draft, invoice_type: :supplier, partner: invoice.partner, fiscal_year: invoice.fiscal_year)
    attach(other, :pdf_document, sample_pdf("fine"), "application/pdf")

    result = described_class.call

    expect(result[:imported]).to eq(1)
    expect(result[:refused].size).to eq(1)
  end

  it "only touches the current entity" do
    foreign = ActsAsTenant.with_tenant(create(:entity)) do
      create(:invoice, :draft, invoice_type: :supplier, partner: create(:partner, :supplier)).tap { |i| attach(i, :pdf_document, sample_pdf("theirs"), "application/pdf") }
    end

    described_class.call

    expect(ActsAsTenant.with_tenant(foreign.entity) { Accounting::Document.count }).to eq(0)
  end
end
