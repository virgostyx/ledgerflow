require "rails_helper"

# The documents kept from a Peppol invoice (original XML, embedded PDF) and its references, on the invoice page.
RSpec.describe "Invoice documents received through Peppol", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:supplier) { create(:partner, :supplier) }
  let(:pdf) { "%PDF-1.4\nbody\n%%EOF\n" }
  let(:xml) { "<Invoice><ID>SUP-1</ID></Invoice>" }
  let(:invoice) do
    create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year,
           order_reference: "PO-2026-014", buyer_reference: "PRJ-ZM-3.2.1").tap do |i|
      i.ubl_document.attach(io: StringIO.new(xml), filename: "SUP-1.xml", content_type: "application/xml")
      i.pdf_document.attach(io: StringIO.new(pdf), filename: "SUP-1.pdf", content_type: "application/pdf")
    end
  end

  before { sign_in accountant }

  it "shows the references and the links to the documents on the invoice page" do
    get accounting_invoice_path(invoice)

    expect(response.body).to include("Peppol document").and include("PO-2026-014").and include("PRJ-ZM-3.2.1")
    expect(response.body).to include(document_accounting_invoice_path(invoice, kind: "xml"))
    expect(response.body).to include(document_accounting_invoice_path(invoice, kind: "pdf"))
  end

  it "shows nothing for an invoice that came with no documents or references" do
    plain = create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)

    get accounting_invoice_path(plain)

    expect(response.body).not_to include("Peppol document")
  end

  it "downloads the original XML as an attachment" do
    get document_accounting_invoice_path(invoice, kind: "xml")

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(xml)
    expect(response.media_type).to eq("application/xml")
    expect(response.headers["Content-Disposition"]).to start_with("attachment").and include("SUP-1.xml")
  end

  it "shows the PDF in the browser" do
    get document_accounting_invoice_path(invoice, kind: "pdf")

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(pdf)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to start_with("inline")
  end

  it "answers 404 for an unknown kind and for a document that was not received" do
    get document_accounting_invoice_path(invoice, kind: "zip")
    expect(response).to have_http_status(:not_found)

    invoice.pdf_document.purge
    get document_accounting_invoice_path(invoice, kind: "pdf")
    expect(response).to have_http_status(:not_found)
  end

  it "does not give the documents of another entity's invoice" do
    other = create(:entity)
    foreign = ActsAsTenant.with_tenant(other) do
      create(:invoice, :draft, invoice_type: :supplier, partner: create(:partner, :supplier), fiscal_year: create(:fiscal_year, entity: other))
        .tap { |i| i.pdf_document.attach(io: StringIO.new(pdf), filename: "x.pdf", content_type: "application/pdf") }
    end

    get document_accounting_invoice_path(foreign, kind: "pdf")

    expect(response).to have_http_status(:not_found)
  end

  it "requires a signed-in user" do
    sign_out accountant

    get document_accounting_invoice_path(invoice, kind: "pdf")

    expect(response).to redirect_to(new_user_session_path)
  end
end
