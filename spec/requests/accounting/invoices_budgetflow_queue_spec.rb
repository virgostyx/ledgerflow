require "rails_helper"

# The queue of what BudgetFlow sent, inside the regular purchases list: a banner with the drafts to process, a filter, a badge
# and the project context on each row. Nothing of it for an entity that does not use BudgetFlow.
RSpec.describe "Invoices received from BudgetFlow (queue)", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:acme)  { create(:partner, :supplier, name: "ACME Zambia Supplies") }
  let(:local) { create(:partner, :supplier, name: "Local Typed Supplier") }
  let!(:from_budgetflow) do
    create(:invoice, :draft, invoice_type: :supplier, partner: acme, fiscal_year: fiscal_year, external_digest: "x",
           external_project_name: "Water Access Zambia", external_budget_line: "3.2.1")
  end
  let!(:typed) { create(:invoice, :draft, invoice_type: :supplier, partner: local, fiscal_year: fiscal_year) }

  before { sign_in accountant }

  context "when the entity uses BudgetFlow" do
    it "shows a banner counting the drafts to process, linking to the filtered list" do
      get accounting_purchases_path

      expect(response.body).to include("1 invoice from BudgetFlow to process")
      expect(response.body).to include("q%5Bsource%5D=1").or include("q[source]=1")
    end

    it "shows the BudgetFlow badge and the project context on its rows only" do
      get accounting_purchases_path

      expect(response.body).to include("Water Access Zambia").and include("3.2.1")
      expect(response.body.scan("BudgetFlow</span>").size).to eq(1)
    end

    it "filters to what BudgetFlow sent" do
      get accounting_purchases_path, params: { q: { source: "1" } }

      expect(response.body).to include("ACME Zambia Supplies")
      expect(response.body).not_to include("Local Typed Supplier")
    end

    it "has no banner once nothing is left to process" do
      from_budgetflow.update_columns(status: Accounting::Invoice.statuses[:cancelled])

      get accounting_purchases_path

      expect(response.body).not_to include("from BudgetFlow to process")
    end
  end

  # Credit notes mix with invoices in the list: a badge says which they are, and a filter keeps only them.
  describe "credit notes in the list" do
    let!(:credit_note) do
      create(:invoice, :draft, invoice_type: :supplier, partner: create(:partner, :supplier, name: "Refunding Supplier"), fiscal_year: fiscal_year,
             document_type: :credit_note)
    end

    it "shows a Credit note badge on a credit note and on nothing else" do
      get accounting_purchases_path

      expect(response.body.scan("Credit note</span>").size).to eq(1)
    end

    it "keeps only the credit notes with the filter" do
      get accounting_purchases_path, params: { q: { credit_notes: "1" } }

      expect(response.body).to include("Refunding Supplier")
      expect(response.body).not_to include("ACME Zambia Supplies")
      expect(response.body).not_to include("Local Typed Supplier")
    end

    it "offers the filter" do
      get accounting_purchases_path

      expect(response.body).to include("Credit notes only")
    end
  end

  # BudgetFlow believes what it sent: a deleted draft would stay "exported" there for ever. The accountant returns it instead, which tells BudgetFlow.
  describe "deleting a draft" do
    it "is refused for a draft BudgetFlow sent, with the way to do it, and the draft stays" do
      expect { delete accounting_invoice_path(from_budgetflow) }.not_to change(Accounting::Invoice, :count)

      expect(response).to redirect_to(accounting_invoice_path(from_budgetflow))
      expect(flash[:alert]).to include("BudgetFlow").and include("return")
    end

    it "offers no Delete button on a draft BudgetFlow sent, but one on a draft typed here" do
      get accounting_purchases_path

      expect(response.body.scan("Delete this draft invoice?").size).to eq(1)
    end

    it "still deletes a draft typed in LedgerFlow" do
      expect { delete accounting_invoice_path(typed) }.to change(Accounting::Invoice, :count).by(-1)
    end

    it "is allowed for an entity that does not use BudgetFlow (nobody there is waiting for the draft)" do
      entity.update!(budgetflow_enabled: false)

      expect { delete accounting_invoice_path(from_budgetflow) }.to change(Accounting::Invoice, :count).by(-1)
    end

    it "leaves returning it to the project manager possible, which cancels the draft and tells BudgetFlow" do
      expect { post return_invoice_accounting_invoice_path(from_budgetflow), params: { reason: "Wrong project" } }
        .to change { Accounting::InvoiceEvent.where(event_type: "returned").count }.by(1)
    end
  end

  context "a Peppol invoice not yet taken over by BudgetFlow" do
    let(:peppol) { create(:partner, :supplier, name: "Peppol Supplier") }
    let!(:received) do
      create(:invoice, :draft, invoice_type: :supplier, partner: peppol, fiscal_year: fiscal_year).tap do |i|
        i.ubl_document.attach(io: StringIO.new("<Invoice/>"), filename: "x.xml", content_type: "application/xml")
      end
    end

    it "carries a Peppol badge for the accountant, who knows BudgetFlow may take it" do
      get accounting_purchases_path

      expect(response.body.scan("Peppol</span>").size).to eq(1)
    end

    it "loses it once taken over (it then shows as a BudgetFlow invoice)" do
      received.update_columns(external_digest: "claimed", external_ref: "bf-invoice-1")

      get accounting_purchases_path

      expect(response.body).not_to include("Peppol</span>")
    end

    it "shows no badge for an entity that does not use BudgetFlow" do
      entity.update!(budgetflow_enabled: false)

      get accounting_purchases_path

      expect(response.body).not_to include("Peppol</span>")
    end
  end

  context "when the entity does not use BudgetFlow" do
    before { entity.update!(budgetflow_enabled: false) }

    it "shows nothing of it and ignores a forced filter" do
      get accounting_purchases_path, params: { q: { source: "1" } }

      expect(response.body).to include("ACME Zambia Supplies").and include("Local Typed Supplier")
      expect(response.body).not_to include("BudgetFlow")
      expect(response.body).not_to include("Water Access Zambia")
    end
  end
end
