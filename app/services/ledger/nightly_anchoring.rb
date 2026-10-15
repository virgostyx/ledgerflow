# B03c: the anchor of the day, for every company that turned the feature on (`b03c`). The first anchor of a company covers what was validated before the fingerprints existed
# (retroactive, said as such on every certificate it covers); the others are nightly. A company whose books cannot be anchored is told in its audit trail and does not hold the
# others back: that is the signal of a book that is not whole.
module Ledger::NightlyAnchoring
  def self.call
    Entity.where(active: true).find_each do |entity|
      next unless entity.feature?(:b03c)

      ActsAsTenant.with_tenant(entity) { anchor(entity) }
    end
  end

  def self.anchor(entity)
    anchor = Ledger::Anchoring.call(kind: first_anchor_needed? ? "retroactive" : "nightly")
    Ledger::Timestamping.call(anchor, transport: Ledger::Timestamping.default_transport) if anchor # best effort: without a token the anchor stands, and the hourly job tries again
    anchor
  rescue Ledger::Anchoring::Refused => e
    Accounting::AuditLog.record!(auditable: entity, action: "anchoring_refused", actor_type: "user", payload: { reason: e.message })
    nil
  end
  private_class_method :anchor

  # No anchor yet, and entries that were not fingerprinted when they were validated.
  def self.first_anchor_needed?
    return false if Ledger::Anchor.exists?

    Accounting::JournalEntry.where.not(posted_seq: nil).where("content_hash IS NULL OR content_hash_source <> 'live'").exists?
  end
  private_class_method :first_anchor_needed?
end
