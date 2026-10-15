require Rails.root.join("tools/ledger-verify/lib/ledger_verify/canonical")

# B03c: an anchor of the books (table `ledger_anchors`, never changed by anyone: see the migration). It binds the fingerprints of the entries validated since the previous anchor
# (the Merkle root), the head of the audit chain, and the previous anchor. Made by Ledger::Anchoring; checked by Ledger::AnchorChain.
class Ledger::Anchor < ApplicationRecord
  self.table_name = "ledger_anchors"

  KINDS = %w[nightly on_demand retroactive].freeze

  acts_as_tenant :entity

  validates :kind, inclusion: { in: KINDS }

  scope :chronological, -> { order(:number) }

  # SHA-256 of the canonical JSON (RFC 8785) of what the anchor binds: `ledger-verify` writes the same object.
  def self.hash_of(anchor)
    Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate(
      "previous" => anchor.previous_anchor_hash, "from_seq" => anchor.from_seq, "to_seq" => anchor.to_seq, "root" => anchor.merkle_root, "count" => anchor.entries_count,
      "audit_head" => anchor.audit_head, "audit_length" => anchor.audit_length, "anchored_at" => anchor.anchored_at.utc.iso8601(6)
    ))
  end
end
