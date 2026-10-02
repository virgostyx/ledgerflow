require "rails_helper"

RSpec.describe "Accounting::DocumentLinks", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:reader)     { create(:user, role: :auditor) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:reader_membership)     { create(:user_entity, :manager, user: reader, entity: entity) }
  let(:document) { create(:document) }
  let(:entry)    { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, reference: "ACH-1") }

  before { sign_in accountant }

  describe "POST /accounting/document_links" do
    it "attaches the document to an entry and returns to the entry" do
      post accounting_document_links_path, params: { document_id: document.id, target_type: "entry", target_id: entry.id }

      expect(response).to redirect_to(accounting_journal_entry_path(entry))
      expect(document.links.sole.target).to eq(entry)
      expect(document.reload).to be_linked
    end

    it "attaches by entry reference from the document page" do
      entry # the entry exists before the request
      post accounting_document_links_path, params: { document_id: document.id, entry_reference: "ACH-1" }

      expect(response).to redirect_to(accounting_document_path(document))
      expect(document.links.sole.target).to eq(entry)
    end

    it "says when the reference matches nothing" do
      post accounting_document_links_path, params: { document_id: document.id, entry_reference: "NOPE" }

      expect(document.links).to be_empty
      expect(flash[:alert]).to match(/no entry/i)
    end

    it "attaches to a partner too" do
      partner = create(:partner)

      post accounting_document_links_path, params: { document_id: document.id, target_type: "partner", target_id: partner.id }

      expect(document.links.sole.target).to eq(partner)
    end

    it "refuses a kind of target it does not know" do
      post accounting_document_links_path, params: { document_id: document.id, target_type: "User", target_id: accountant.id }

      expect(document.links).to be_empty
    end

    it "refuses an entry of another entity, as if it did not exist" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:journal_entry) }

      post accounting_document_links_path, params: { document_id: document.id, target_type: "entry", target_id: foreign.id }

      expect(document.links).to be_empty
      expect(response).to have_http_status(:not_found)
    end

    it "refuses a document of another entity" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:document) }

      post accounting_document_links_path, params: { document_id: foreign.id, target_type: "entry", target_id: entry.id }

      expect(response).to have_http_status(:not_found)
    end

    it "is refused to a reader" do
      sign_out accountant
      sign_in reader

      post accounting_document_links_path, params: { document_id: document.id, target_type: "entry", target_id: entry.id }

      expect(document.links).to be_empty
    end
  end

  describe "DELETE /accounting/document_links/:id" do
    it "detaches a document from a draft entry" do
      Accounting::LinkDocument.call(document: document, target: entry, user: accountant)

      delete accounting_document_link_path(document.links.sole)

      expect(document.reload.links).to be_empty
      expect(document).to be_inbox
    end

    it "keeps what justifies a validated entry attached, and says so" do
      Accounting::PostJournalEntry.call(entry: entry)
      Accounting::LinkDocument.call(document: document, target: entry.reload, user: accountant)

      delete accounting_document_link_path(document.links.sole)

      expect(document.links.count).to eq(1)
      expect(flash[:alert]).to match(/validated entry/i)
    end

    it "is refused to a reader" do
      Accounting::LinkDocument.call(document: document, target: entry, user: accountant)
      sign_out accountant
      sign_in reader

      delete accounting_document_link_path(document.links.sole)

      expect(document.links.count).to eq(1)
    end
  end

  describe "the documents of an entry (three clicks from the trial balance: account, entry, document)" do
    it "lists them on the entry page, each leading to its viewer" do
      Accounting::LinkDocument.call(document: document, target: entry, user: accountant)

      get accounting_journal_entry_path(entry)

      expect(response.body).to include(document.name, accounting_document_path(document))
    end

    it "offers the inbox documents to attach" do
      inbox = create(:document, name: "waiting-in-inbox.pdf")

      get accounting_journal_entry_path(entry)

      expect(response.body).to include("waiting-in-inbox.pdf", accounting_document_links_path)
      expect(inbox).to be_inbox
    end

    it "does not offer to attach to a reader, who may still see the documents" do
      Accounting::LinkDocument.call(document: document, target: entry, user: accountant)
      create(:document, name: "waiting-in-inbox.pdf")
      sign_out accountant
      sign_in reader

      get accounting_journal_entry_path(entry)

      expect(response.body).to include(document.name)
      expect(response.body).not_to include("waiting-in-inbox.pdf")
    end

    it "shows nothing about documents while the feature is off" do
      Accounting::LinkDocument.call(document: document, target: entry, user: accountant)
      entity.update!(features: { "f03" => false })

      get accounting_journal_entry_path(entry)

      expect(response.body).not_to include(document.name)
    end
  end
end
