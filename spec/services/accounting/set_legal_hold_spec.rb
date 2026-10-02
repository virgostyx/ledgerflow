require "rails_helper"

# A legal hold suspends the end of the retention period: nothing is deleted while it lasts (F03).
RSpec.describe Accounting::SetLegalHold do
  include_context "with entity"

  let(:user)     { create(:user) }
  let(:document) { create(:document) }

  def audit = Accounting::AuditLog.where(action: "document_legal_hold", auditable_id: document.id)

  it "places the hold, with the reason and who asked" do
    result = described_class.call(document: document, hold: true, reason: "Tax audit 2026", user: user)

    expect(result).to be_success
    expect(document.reload).to have_attributes(legal_hold: true, legal_hold_reason: "Tax audit 2026")
  end

  it "needs a reason to place it" do
    result = described_class.call(document: document, hold: true, reason: " ", user: user)

    expect(result).to be_failure
    expect(document.reload.legal_hold).to be false
    expect(audit).to be_empty
  end

  it "keeps the document from being deleted, even after its term" do
    described_class.call(document: document, hold: true, reason: "Dispute", user: user)

    travel_to(document.retention_until + 1) { expect(document.reload.destroy).to be false }
  end

  it "releases it, and the term applies again" do
    described_class.call(document: document, hold: true, reason: "Dispute", user: user)

    result = described_class.call(document: document, hold: false, reason: "Settled", user: user)

    expect(result).to be_success
    expect(document.reload).to have_attributes(legal_hold: false, legal_hold_reason: nil)
    travel_to(document.retention_until + 1) { expect(document.deletable?).to be true }
  end

  it "audits both, with the reason" do
    described_class.call(document: document, hold: true, reason: "Dispute", user: user)
    described_class.call(document: document, hold: false, reason: "Settled", user: user)

    expect(audit.order(:id).map { |row| [ row.payload["hold"], row.reason ] }).to eq([ [ true, "Dispute" ], [ false, "Settled" ] ])
    expect(audit.pluck(:user_id).uniq).to eq([ user.id ])
  end

  it "does nothing when there is nothing to change" do
    described_class.call(document: document, hold: true, reason: "Dispute", user: user)

    expect { described_class.call(document: document, hold: true, reason: "Again", user: user) }.not_to change { audit.count }
    expect(document.reload.legal_hold_reason).to eq("Dispute")
  end

  it "works on a document frozen by a validated entry: it is a retention control, not a change to the evidence" do
    Accounting::LinkDocument.call(document: document, target: create(:journal_entry, :posted), user: user)

    expect(described_class.call(document: document, hold: true, reason: "Dispute", user: user)).to be_success
    expect(document.reload.legal_hold).to be true
  end

  it "still refuses to change the details of a frozen document" do
    Accounting::LinkDocument.call(document: document, target: create(:journal_entry, :posted), user: user)
    described_class.call(document: document, hold: true, reason: "Dispute", user: user)

    expect { document.reload.update!(kind: :contract) }.to raise_error(Accounting::ImmutableRecordError)
  end
end
