require "rails_helper"
require Rails.root.join("tools/ledger-verify/lib/ledger_verify/audit_chain")

# B03c critère 11 (évolution de R18): the chain of version 2 keeps the digest of the content of each event, and links the events by SHA-256(previous hash || content digest ||
# metadata): a third party verifies it without reading any content. It starts at the activation, on the head of the version 1; no existing event is touched.
RSpec.describe "Audit trail chain, version 2 (R18)", type: :model do
  include_context "with entity"

  let!(:account) { create(:account) } # creating it is itself audited

  def log(action = "test", **attrs) = Accounting::AuditLog.record!(auditable: account, action: action, **attrs)

  # A row as the application wrote them before version 2: the hash covers the content itself.
  def legacy_row(action, previous:)
    row = Accounting::AuditLog.new(auditable_type: "Accounting::Account", auditable_id: account.id, action: action, user_email: "someone@example.test", payload: { "n" => 1 }, entity_id: entity.id,
                                   previous_hash: previous, created_at: Time.current.utc.round(6))
    row.content_hash = Accounting::AuditLog.digest_v1(row)
    ActsAsTenant.without_tenant { row.save! }
    row
  end

  def wipe_chain = ActsAsTenant.without_tenant { tamper(:accounting_audit_logs) { Accounting::AuditLog.unscoped.where(entity_id: entity.id).delete_all } }

  describe "an event written now" do
    it "is of version 2: the digest of its content (canonical JSON), and a hash that links the digest, the metadata and the previous hash" do
      first = log("a", payload: { amount: "10.00" })
      second = log("b", reason: "because")

      expect(second.chain_version).to eq(2)
      expect(second.content_digest).to eq(Digest::SHA256.hexdigest(Accounting::AuditLog.content_json(second)))
      metadata = LedgerVerify::Canonical.generate("action" => "b", "actor_type" => "user", "auditable_id" => account.id, "auditable_type" => "Accounting::Account",
                                                  "created_at" => second.created_at.utc.iso8601(6), "entity_id" => entity.id)
      expect(second.content_hash).to eq(Digest::SHA256.hexdigest("#{first.content_hash}#{second.content_digest}#{metadata}"))
      expect(second.previous_hash).to eq(first.content_hash)
      expect(second.content_hash).to eq(Accounting::AuditLog.digest(second))
    end

    it "keeps its content out of the metadata: the e-mail, the address and the payload are in the digest only" do
      row = log("a", payload: { secret: "x" })

      expect(Accounting::AuditLog.metadata_json(row)).not_to include("x", "@", "payload")
    end
  end

  describe "the switch from version 1" do
    before do
      wipe_chain
      @v1 = [ legacy_row("old-1", previous: nil) ]
      @v1 << legacy_row("old-2", previous: @v1.last.content_hash)
    end

    it "is an event of its own, on the head of version 1, written before the first event of version 2; the old events are not touched" do
      before = Accounting::AuditLog.unscoped.where(id: @v1.map(&:id)).pluck(:id, :content_hash, :chain_version, :previous_hash)

      event = log("first-v2")

      switch = Accounting::AuditLog.unscoped.where(entity_id: entity.id, action: "audit_chain_version_2").sole
      expect(switch).to have_attributes(previous_hash: @v1.last.content_hash, chain_version: 2)
      expect(event.previous_hash).to eq(switch.content_hash)
      expect(Accounting::AuditLog.unscoped.where(id: @v1.map(&:id)).pluck(:id, :content_hash, :chain_version, :previous_hash)).to eq(before)
      expect(@v1.map { |r| r.reload.chain_version }).to all(be_nil)
    end

    it "happens once" do
      log("a")
      log("b")

      expect(Accounting::AuditLog.unscoped.where(entity_id: entity.id, action: "audit_chain_version_2").count).to eq(1)
    end

    it "is verified as a whole by the application, the old part with its content, the new one with its digests" do
      log("a")
      log("b")

      result = Accounting::AuditVerifier.call(entity: entity)

      expect(result).to be_intact
      expect(result.count).to eq(Accounting::AuditLog.unscoped.where(entity_id: entity.id).count)
      expect(result.version_1).to eq(2)
    end

    it "starts straight in version 2 for a company without history" do
      wipe_chain

      expect(log("a").chain_version).to eq(2)
      expect(Accounting::AuditLog.unscoped.where(entity_id: entity.id, action: "audit_chain_version_2")).to be_empty
    end
  end

  describe "verified by a third party, without the content" do
    def exported = Ledger::AuditChainExport.rows(entity)

    before do
      wipe_chain
      v1 = legacy_row("old-1", previous: nil)
      legacy_row("old-2", previous: v1.content_hash)
      3.times { |i| log("new-#{i}", payload: { n: i }, reason: "personal #{i}") }
    end

    it "gives, for each event, its digest, its metadata, the previous hash and its hash, and nothing of its content" do
      rows = exported

      expect(rows.size).to eq(Accounting::AuditLog.unscoped.where(entity_id: entity.id).count)
      expect(rows.last.keys).to match_array(%w[id version content_digest metadata previous_hash hash])
      expect(rows.to_json).not_to include("someone@example.test")
      expect(rows.to_json).to include(rows.last["content_digest"])
      expect(rows.first["version"]).to eq(1)
      expect(rows.first["content_digest"]).to be_nil
    end

    it "passes with the verifier of the tool, and says how much of it only linked (version 1)" do
      result = LedgerVerify::AuditChain.verify(exported)

      expect(result).to be_ok
      expect(result.checked).to eq(exported.size)
      expect(result.linked_only).to eq(2)
    end

    it "fails on the first event that was changed: a digest, a metadata, a link, a removed event, a version put back" do
      rows = exported
      victim = rows.last(2).first

      expect(LedgerVerify::AuditChain.verify(rows.map { |r| r["id"] == victim["id"] ? r.merge("content_digest" => "0" * 64) : r }).broken_id).to eq(victim["id"])
      expect(LedgerVerify::AuditChain.verify(rows.map { |r| r["id"] == victim["id"] ? r.merge("metadata" => r["metadata"].merge("action" => "other")) : r }).broken_id).to eq(victim["id"])
      expect(LedgerVerify::AuditChain.verify(rows.map { |r| r["id"] == victim["id"] ? r.merge("previous_hash" => "1" * 64) : r }).broken_id).to eq(victim["id"])
      expect(LedgerVerify::AuditChain.verify(rows.reject { |r| r["id"] == victim["id"] }).broken_id).to eq(rows.last["id"])
      expect(LedgerVerify::AuditChain.verify(rows.map { |r| r["id"] == victim["id"] ? r.merge("version" => 1) : r }).broken_id).to eq(victim["id"])
    end
  end

  describe "the verifier of the application" do
    it "names the event whose digest, hash or link was changed behind its back, in both versions" do
      log("a")
      victim = log("b", payload: { amount: "10.00" })
      log("c")
      ActsAsTenant.without_tenant { tamper(:accounting_audit_logs) { Accounting::AuditLog.unscoped.where(id: victim.id).update_all(payload: { amount: "99.00" }) } }

      expect(Accounting::AuditVerifier.call(entity: entity).broken_id).to eq(victim.id)
    end

    it "refuses a version 1 event that comes after a version 2 one (the chain cannot go back)" do
      head = log("a")
      legacy_row("late-legacy", previous: head.content_hash)

      expect(Accounting::AuditVerifier.call(entity: entity)).not_to be_intact
    end

    it "counts what is not chained (an event without hash), to tell it" do
      log("a")
      ActsAsTenant.without_tenant { tamper(:accounting_audit_logs) { Accounting::AuditLog.insert!({ auditable_type: "Accounting::Account", auditable_id: account.id, action: "unchained", entity_id: entity.id, created_at: Time.current, updated_at: Time.current, payload: {} }) } }

      expect(Accounting::AuditVerifier.call(entity: entity).unchained).to eq(1)
    end
  end
end
