require "rails_helper"

RSpec.describe Accounting::Document, type: :model do
  include_context "with entity"

  describe "validations" do
    it "is valid with a file" do
      expect(build(:document)).to be_valid
    end

    it "needs a file, a name and a checksum" do
      document = described_class.new(entity: entity, name: nil, sha256: nil)

      expect(document).not_to be_valid
      expect(document.errors.attribute_names).to include(:name, :sha256, :file)
    end

    it "refuses a second document with the same content in the same entity" do
      first = create(:document, content: sample_pdf("same"))

      second = build(:document, content: sample_pdf("same"))

      expect(second).not_to be_valid
      expect(second.errors[:sha256]).to be_present
      expect(first).to be_persisted
    end

    it "accepts the same content in another entity" do
      create(:document, content: sample_pdf("same"))

      other = create(:entity)
      ActsAsTenant.with_tenant(other) { expect(build(:document, content: sample_pdf("same"))).to be_valid }
    end
  end

  describe "defaults" do
    it "lands in the inbox, uploaded manually, kind other" do
      document = create(:document)

      expect(document).to be_inbox
      expect(document).to be_manual_upload
      expect(document).to be_other
    end

    it "keeps the document ten years (to be confirmed with the accounting rules, see QUESTIONS.md)" do
      expect(create(:document).retention_until).to eq(Date.current + 10.years)
    end

    it "is under no legal hold" do
      expect(create(:document).legal_hold).to be false
    end
  end

  describe "retention depends on the kind of document" do
    it "keeps each kind for the years set for it (ten by default), counted from the day of upload" do
      stub_const("Accounting::Document::RETENTION_YEARS_BY_KIND", Hash.new(10).merge("contract" => 30, "statement" => 7))

      expect(create(:document, kind: :other).retention_until).to eq(Date.current + 10.years)
      expect(create(:document, kind: :contract).retention_until).to eq(Date.current + 30.years)
      expect(create(:document, kind: :statement).retention_until).to eq(Date.current + 7.years)
    end

    it "follows a change of kind" do
      stub_const("Accounting::Document::RETENTION_YEARS_BY_KIND", Hash.new(10).merge("contract" => 30))
      document = create(:document, kind: :other)

      document.update!(kind: :contract)

      expect(document.retention_until).to eq(document.created_at.to_date + 30.years)
    end

    it "does not shorten a term on a legal hold" do
      stub_const("Accounting::Document::RETENTION_YEARS_BY_KIND", Hash.new(10).merge("statement" => 7))
      document = create(:document, kind: :other, legal_hold: true, legal_hold_reason: "Dispute")

      document.update!(kind: :statement)

      expect(document.retention_until).to eq(Date.current + 10.years)
    end

    it "never shortens a term that was already running longer" do
      stub_const("Accounting::Document::RETENTION_YEARS_BY_KIND", Hash.new(10).merge("statement" => 7))
      document = create(:document, kind: :other)

      document.update!(kind: :statement)

      expect(document.retention_until).to eq(Date.current + 10.years)
    end
  end

  describe "a file never changes" do
    let(:document) { create(:document) }

    it "refuses another file under the same document (a new version is a new document)" do
      document.file.attach(io: StringIO.new(sample_pdf("other")), filename: "x.pdf")

      expect(document).not_to be_valid
      expect(document.errors[:file]).to be_present
    end

    it "keeps the checksum and the size read-only" do
      expect { document.update!(sha256: "0" * 64) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    end

    it "points to the document it replaces" do
      newer = create(:document, replaces: document, content: sample_pdf("v2"))

      expect(newer.replaces).to eq(document)
    end
  end

  describe "links" do
    let(:document) { create(:document) }

    it "may be linked to several targets" do
      entry = create(:journal_entry)
      partner = create(:partner)

      document.links.create!(target: entry)
      document.links.create!(target: partner)

      expect(document.links.count).to eq(2)
    end

    it "is linked to the same target only once" do
      entry = create(:journal_entry)
      document.links.create!(target: entry)

      expect(document.links.build(target: entry)).not_to be_valid
    end

    it "is lettered by what it is linked to: an entry may have several documents" do
      entry = create(:journal_entry)
      other = create(:document)

      document.links.create!(target: entry)
      other.links.create!(target: entry)

      expect(Accounting::DocumentLink.where(target: entry).count).to eq(2)
    end
  end

  describe "#locked? (linked to a validated entry)" do
    let(:document) { create(:document) }

    it "is not locked while linked only to a draft, a partner or nothing" do
      document.links.create!(target: create(:journal_entry))
      document.links.create!(target: create(:partner))

      expect(document).not_to be_locked
    end

    it "is locked once linked to a validated entry" do
      document.links.create!(target: create(:journal_entry, :posted))

      expect(document).to be_locked
    end

    it "refuses any change except archiving when locked" do
      document.links.create!(target: create(:journal_entry, :posted))

      expect { document.update!(kind: :purchase_invoice) }.to raise_error(Accounting::ImmutableRecordError)
      expect { document.update!(name: "renamed.pdf") }.to raise_error(Accounting::ImmutableRecordError)
    end

    it "lets a locked document be archived" do
      document.links.create!(target: create(:journal_entry, :posted))

      expect { document.update!(status: :archived) }.not_to raise_error
      expect(document.reload).to be_archived
    end

    it "lets an unlocked document be reclassified" do
      expect { document.update!(kind: :purchase_invoice) }.not_to raise_error
    end
  end

  describe "deleting" do
    let(:document) { create(:document) }

    it "is refused before the end of the retention period" do
      expect(document.destroy).to be false
      expect(described_class.exists?(document.id)).to be true
    end

    it "is refused under a legal hold, even after the term" do
      document.update!(legal_hold: true, legal_hold_reason: "Dispute")

      travel_to(document.retention_until + 1) { expect(document.destroy).to be false }
    end

    it "is possible after the term, which also removes its links" do
      document.links.create!(target: create(:partner))

      travel_to(document.retention_until + 1) do
        expect { document.destroy }.to change(described_class, :count).by(-1).and change(Accounting::DocumentLink, :count).by(-1)
      end
    end
  end

  describe "scoping" do
    it "is invisible from another entity" do
      document = create(:document)

      ActsAsTenant.with_tenant(create(:entity)) { expect(described_class.find_by(id: document.id)).to be_nil }
    end
  end
end
