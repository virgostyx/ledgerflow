# B03c: the audit chain of a company as a third party may read it: for each event, its version, its content digest, its metadata, the previous hash and its hash - never its content.
# The events of version 1, written before the digests, only have their links (they hashed their content: nothing of it is given). Events with no hash are not part of the chain.
module Ledger::AuditChainExport
  def self.rows(entity)
    Accounting::AuditLog.unscoped.where(entity_id: entity.id).where.not(content_hash: nil).order(:id).map do |row|
      v2 = row.chain_version == 2
      { "id" => row.id, "version" => v2 ? 2 : 1, "content_digest" => (row.content_digest if v2), "metadata" => (JSON.parse(Accounting::AuditLog.metadata_json(row)) if v2),
        "previous_hash" => row.previous_hash, "hash" => row.content_hash }
    end
  end
end
