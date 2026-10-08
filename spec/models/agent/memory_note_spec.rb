require "rails_helper"

RSpec.describe Agent::MemoryNote do
  include_context "with entity"

  let(:author) { create(:user) }
  let(:partner) { create(:partner, :supplier, name: "Fournisseur Dupont SA", vat_number: nil) }

  def note(**attrs) = described_class.create!({ scope_kind: "entity", text: "Everything is invoiced in euros.", category: "convention", author: author }.merge(attrs))

  it "keeps its text encrypted, at 500 characters at most" do
    kept = note

    expect(ActiveRecord::Base.connection.select_value("SELECT text FROM agent_memory_notes WHERE id = #{kept.id}")).not_to include("euros")
    expect(described_class.new(scope_kind: "entity", text: "x" * 501, category: "other", author: author)).not_to be_valid
  end

  it "is about the whole file, or about a partner or an account that exists in this entity" do
    expect(note(scope_kind: "partner", scope_id: partner.id)).to be_persisted
    expect(described_class.new(scope_kind: "partner", scope_id: 0, text: "x", category: "other", author: author)).not_to be_valid
    expect(described_class.new(scope_kind: "partner", text: "x", category: "other", author: author)).not_to be_valid
    expect(described_class.new(scope_kind: "invoice", scope_id: 1, text: "x", category: "other", author: author)).not_to be_valid
  end

  it "is read only while active and not past its date" do
    live = note
    ended = note(valid_until: Date.current - 1)
    archived = note(status: "archived")

    expect(described_class.active).to contain_exactly(live)
    expect(ended.active?).to be false
    expect(archived.active?).to be false
  end

  it "archives by itself the notes whose date has passed" do
    ended = note(valid_until: Date.current - 1)
    kept = note(valid_until: Date.current + 1)

    described_class.archive_expired!

    expect(ended.reload.status).to eq("archived")
    expect(kept.reload.status).to eq("active")
  end

  it "counts its uses, and a note not used for a year is suggested for archiving" do
    old = note.tap { |n| n.update_columns(created_at: 13.months.ago) }
    used = note.tap { |n| n.update_columns(created_at: 13.months.ago) }
    described_class.used!([ used.id ])

    expect(used.reload).to have_attributes(uses_count: 1)
    expect(used.last_used_at).to be_within(1.minute).of(Time.current)
    expect(described_class.unused).to contain_exactly(old)
  end

  it "says when the object it was about is gone" do
    kept = note(scope_kind: "partner", scope_id: partner.id)
    partner.destroy

    expect(kept.reload.object_missing?).to be true
  end

  it "is archived by the retention job when its date has passed" do
    ended = note(valid_until: Date.current - 1)

    Agent::RetentionJob.perform_now

    expect(ended.reload.status).to eq("archived")
  end
end
