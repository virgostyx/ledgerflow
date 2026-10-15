require Rails.root.join("tools/ledger-verify/lib/ledger_verify/merkle")

# B03c: makes the anchor of the day (`nightly`), the one a certificate asks for (`on_demand`), or the single one that covers what was validated before the fingerprints existed
# (`retroactive`: it fingerprints those entries, and says how many).
#
# One at a time per company (an advisory lock held to the end of the transaction). It binds the entries validated since the previous anchor, in the order of `posted_seq`, and
# the head of the audit chain; nothing is made when neither has moved. Making an anchor writes nothing in the audit chain, which would otherwise never stop moving.
#
# => the anchor, or nil when there was nothing to bind. Raises Refused when an entry cannot be fingerprinted or the places of the entries have a hole: what cannot be anchored
# is not to be passed over.
module Ledger::Anchoring
  class Refused < StandardError; end

  def self.call(kind:)
    raise ArgumentError, "kind: #{Ledger::Anchor::KINDS.join(', ')}" unless Ledger::Anchor::KINDS.include?(kind)

    entity = ActsAsTenant.current_tenant
    Ledger::Anchor.transaction do
      ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(hashtext('ledger_anchor'), #{entity.id.to_i})")
      last = Ledger::Anchor.chronological.last
      raise Refused, "the retroactive anchor is made once, and first" if kind == "retroactive" && last

      from = last ? last.to_seq + 1 : 1
      to = Accounting::JournalEntry.where.not(posted_seq: nil).maximum(:posted_seq) || (from - 1)
      to = [ to, from - 1 ].max
      head = audit_head(entity)
      return nil if last && to < from && last.audit_head == head[:hash] && last.audit_length == head[:length]

      hashes = fingerprints(from, to, kind)
      build(entity, kind, last, from, to, hashes, head)
    end
  end

  def self.fingerprints(from, to, kind)
    return [] if to < from

    Accounting::JournalEntry.where(posted_seq: from..to, content_hash: nil).in_batches(of: 1000) { |batch| Ledger::Seal.many(batch.to_a, source: "retroactive") }
    stuck = Accounting::JournalEntry.where(posted_seq: from..to, content_hash: nil).pluck(:id)
    raise Refused, "the entries #{stuck.join(', ')} have no fingerprint and cannot get one (no line): they cannot be anchored" if stuck.any?

    rows = Accounting::JournalEntry.where(posted_seq: from..to).order(:posted_seq).pluck(:posted_seq, :content_hash, :content_hash_source)
    raise Refused, "the places of the entries have a hole between #{from} and #{to}" unless rows.map(&:first) == (from..to).to_a

    rows.map { |_, hash, source| [ hash, source ] }
  end
  private_class_method :fingerprints

  def self.build(entity, kind, last, from, to, hashes, head)
    anchor = Ledger::Anchor.new(
      number: (last&.number || 0) + 1, kind: kind, from_seq: from, to_seq: to, entries_count: hashes.size, retroactive_entries: hashes.count { |_, source| source != "live" },
      merkle_root: LedgerVerify::Merkle.root_of_hex(hashes.map(&:first)), audit_head: head[:hash], audit_length: head[:length], previous_anchor_hash: last&.anchor_hash,
      anchored_at: ApplicationRecord.connection.select_value("SELECT clock_timestamp() AT TIME ZONE 'UTC'").then { |t| t.is_a?(String) ? Time.utc(*t.scan(/\d+/).map(&:to_i)) : t }
    )
    anchor.anchored_at = anchor.anchored_at.utc.round(6)
    anchor.anchor_hash = Ledger::Anchor.hash_of(anchor)
    anchor.save!
    anchor
  end
  private_class_method :build

  def self.audit_head(entity)
    chained = Accounting::AuditLog.unscoped.where(entity_id: entity.id).where.not(content_hash: nil)
    { hash: chained.order(:id).last&.content_hash, length: chained.count }
  end
  private_class_method :audit_head
end
