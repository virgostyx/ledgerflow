require "rails_helper"

RSpec.describe "Linking a document to what it justifies" do
  include_context "with entity"

  let(:user)     { create(:user) }
  let(:document) { create(:document) }
  let(:entry)    { create(:journal_entry) }

  def audit(action) = Accounting::AuditLog.where(action: action, auditable_id: document.id)

  describe Accounting::LinkDocument do
    it "links the document, which leaves the inbox, and says who did it" do
      result = described_class.call(document: document, target: entry, user: user)

      expect(result).to be_success
      expect(document.links.sole).to have_attributes(target: entry, created_by: user)
      expect(document.reload).to be_linked
    end

    it "audits the link with its target" do
      described_class.call(document: document, target: entry, user: user)

      expect(audit("document_link").sole.payload).to include("target_type" => "Accounting::JournalEntry", "target_id" => entry.id)
    end

    it "links one document to several targets" do
      described_class.call(document: document, target: entry, user: user)
      described_class.call(document: document, target: create(:partner), user: user)

      expect(document.links.count).to eq(2)
    end

    it "refuses to link twice the same target, without a second link or audit" do
      described_class.call(document: document, target: entry, user: user)

      result = described_class.call(document: document, target: entry, user: user)

      expect(result).to be_failure
      expect(document.links.count).to eq(1)
      expect(audit("document_link").count).to eq(1)
    end

    it "locks the document when the entry is validated" do
      validated = create(:journal_entry, :posted)

      described_class.call(document: document, target: validated, user: user)

      expect(document.reload).to be_locked
      expect(document).to be_linked
    end

    it "refuses a target that belongs to another entity" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:journal_entry) }

      result = described_class.call(document: document, target: foreign, user: user)

      expect(result).to be_failure
      expect(document.links).to be_empty
    end

    it "refuses a kind of target that cannot carry a document" do
      expect(described_class.call(document: document, target: user, user: user)).to be_failure
    end

    it "does not link an archived document" do
      document.update!(status: :archived)

      expect(described_class.call(document: document, target: entry, user: user)).to be_failure
    end
  end

  describe Accounting::UnlinkDocument do
    let!(:link) { Accounting::LinkDocument.call(document: document, target: entry, user: user) && document.links.sole }

    it "detaches the document, which goes back to the inbox when nothing else holds it" do
      result = described_class.call(link: link, user: user)

      expect(result).to be_success
      expect(document.links).to be_empty
      expect(document.reload).to be_inbox
    end

    it "audits the detachment" do
      described_class.call(link: link, user: user)

      expect(audit("document_unlink").sole.payload).to include("target_id" => entry.id)
    end

    it "keeps the document linked while another target still holds it" do
      Accounting::LinkDocument.call(document: document, target: create(:partner), user: user)

      described_class.call(link: link, user: user)

      expect(document.reload).to be_linked
    end

    it "refuses to detach evidence of a validated entry" do
      validated = create(:journal_entry, :posted, fiscal_year: entry.fiscal_year, journal: entry.journal)
      Accounting::LinkDocument.call(document: document, target: validated, user: user)

      result = described_class.call(link: document.links.find_by(target: validated), user: user)

      expect(result).to be_failure
      expect(document.links.count).to eq(2)
      expect(audit("document_unlink")).to be_empty
    end

    it "keeps an archived document archived" do
      document.update!(status: :archived)

      described_class.call(link: link, user: user)

      expect(document.reload).to be_archived
    end
  end
end
