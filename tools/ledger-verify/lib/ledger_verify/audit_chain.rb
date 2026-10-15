require "digest"
require_relative "canonical"

# The audit chain (R18) seen from outside: for each event its digest, its metadata, the previous hash and its own hash - never its content. Version 2 of the chain is
#   hash = SHA-256(previous hash || content digest || canonical JSON of the metadata)
# (the hashes in hexadecimal text, the metadata in RFC 8785), so that it can be checked without reading anything personal. The events of version 1, written before it, hashed
# their content: only the links between them can be checked from here, and the verifier says how many there were.
module LedgerVerify
  module AuditChain
    Result = Struct.new(:checked, :linked_only, :broken_id, :reason, keyword_init: true) do
      def ok? = broken_id.nil?
    end

    HEX = /\A\h{64}\z/

    def self.hash_of(previous_hash, content_digest, metadata)
      Digest::SHA256.hexdigest("#{previous_hash}#{content_digest}#{Canonical.generate(metadata)}")
    end

    # `rows`: in order, each { "id", "version" (1 or 2), "content_digest", "metadata", "previous_hash", "hash" }.
    def self.verify(rows)
      previous = nil
      seen_v2 = false
      linked_only = 0
      rows.each do |row|
        id = row["id"]
        return broken(id, "the event is not linked to the one before", rows, linked_only) unless row["previous_hash"] == previous
        return broken(id, "the hash is not a SHA-256", rows, linked_only) unless row["hash"].to_s.match?(HEX)

        if row["version"] == 2
          seen_v2 = true
          return broken(id, "the content digest is not a SHA-256", rows, linked_only) unless row["content_digest"].to_s.match?(HEX)
          return broken(id, "the hash does not follow from the digest and the metadata", rows, linked_only) unless row["hash"] == hash_of(row["previous_hash"], row["content_digest"], row["metadata"])
        elsif seen_v2
          return broken(id, "an event of version 1 after one of version 2", rows, linked_only)
        else
          linked_only += 1
        end
        previous = row["hash"]
      end
      Result.new(checked: rows.size, linked_only: linked_only)
    end

    def self.broken(id, reason, rows, linked_only) = Result.new(checked: rows.size, linked_only: linked_only, broken_id: id, reason: reason)
    private_class_method :broken
  end
end
