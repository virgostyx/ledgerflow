require Rails.root.join("tools/ledger-verify/lib/ledger_verify/merkle")

# B03c, invariant I17: the chain of anchors holds. For each anchor, in order: its number follows the previous one, its range starts where the previous one ended, it is linked to
# the previous anchor's hash, its own hash follows from what it binds, the entries of its range are as many as it says, and their fingerprints give the root it recorded.
# (That the fingerprints themselves still follow from the content of the entries is the work of Integrity::SelfCheck.)
#
# => count of anchors checked, or the number of the first one that does not hold, and why
module Ledger::AnchorChain
  Result = Struct.new(:count, :broken_number, :reason, keyword_init: true) do
    def intact? = broken_number.nil?
  end

  def self.verify(entity)
    previous = nil
    count = 0
    ActsAsTenant.with_tenant(entity) do
      Ledger::Anchor.chronological.find_each do |anchor|
        reason = problem(anchor, previous)
        return Result.new(count: count, broken_number: anchor.number, reason: reason) if reason

        previous = anchor
        count += 1
      end
    end
    Result.new(count: count)
  end

  def self.problem(anchor, previous)
    return "the number does not follow the previous anchor" unless anchor.number == (previous&.number || 0) + 1
    return "the range does not start where the previous anchor ended" unless anchor.from_seq == (previous ? previous.to_seq + 1 : 1)
    return "the link to the previous anchor is cut" unless anchor.previous_anchor_hash == previous&.anchor_hash
    return "the hash of the anchor does not follow from what it binds" unless anchor.anchor_hash == Ledger::Anchor.hash_of(anchor)

    hashes = Accounting::JournalEntry.where(posted_seq: anchor.from_seq..anchor.to_seq).order(:posted_seq).pluck(:posted_seq, :content_hash)
    return "the entries of the range are not the #{anchor.entries_count} the anchor binds" unless hashes.size == anchor.entries_count && hashes.map(&:first) == (anchor.from_seq..anchor.to_seq).to_a
    return "an entry of the range has no fingerprint" if hashes.any? { |_, hash| hash.nil? }

    "the Merkle root of the entries is not the recorded root" unless LedgerVerify::Merkle.root_of_hex(hashes.map(&:last)) == anchor.merkle_root
  end
  private_class_method :problem
end
