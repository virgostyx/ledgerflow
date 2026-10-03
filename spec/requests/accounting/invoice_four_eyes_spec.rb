require "rails_helper"

RSpec.describe "Four eyes on invoices (screens)", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:sale_journal) { create(:journal, :sale) }

  let(:author)   { create(:user, role: :accountant) }
  let(:reviewer) { create(:user, role: :accountant) }
  let!(:author_membership)   { create(:user_entity, :accountant, user: author, entity: entity) }
  let!(:reviewer_membership) { create(:user_entity, :accountant, user: reviewer, entity: entity) }
  let(:invoice) { create(:invoice, :draft, :with_lines, invoice_type: :customer, journal: sale_journal, fiscal_year: fiscal_year, created_by: author) }

  before { entity.update!(four_eyes: true) }

  it "records who writes an invoice" do
    sign_in author
    attrs = { invoice_date: Date.current, partner_id: create(:partner).id, fiscal_year_id: fiscal_year.id }

    post accounting_sales_path, params: { accounting_invoice: attrs }

    expect(Accounting::Invoice.last&.created_by).to eq(author)
  end

  it "does not offer the author to post, and explains" do
    sign_in author

    get accounting_invoice_path(invoice)

    expect(response.body).not_to include("Post invoice")
    expect(response.body).to match(/another person/i)
  end

  it "refuses the author who posts anyway" do
    sign_in author

    post validate_invoice_accounting_invoice_path(invoice)

    expect(invoice.reload).to be_draft
    expect(flash[:alert]).to match(/another person/i)
  end

  it "lets another person post it" do
    sign_in reviewer

    get accounting_invoice_path(invoice)
    expect(response.body).to include("Post invoice")

    post validate_invoice_accounting_invoice_path(invoice)
    expect(invoice.reload).to be_posted
  end

  it "makes whoever duplicates an invoice, or creates a credit note from it, the author of the new draft" do
    posted = create(:invoice, :posted, fiscal_year: fiscal_year)
    sign_in reviewer

    post duplicate_accounting_invoice_path(posted)
    expect(Accounting::Invoice.order(:id).last.created_by).to eq(reviewer)

    post create_credit_note_accounting_invoice_path(posted)
    expect(Accounting::Invoice.credit_note.order(:id).last.created_by).to eq(reviewer)
  end
end
