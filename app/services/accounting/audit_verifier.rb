# Recomputes the audit chain of an entity (R18): every hashed row must carry the hash of its predecessor and its own. Version 1 events hash their content; version 2 ones keep the
# digest of their content (B03c), which must be that of the content, and the hash must follow from it. A version 1 event after a version 2 one is a chain that went back.
# Returns the length checked, or the id of the first row that does not hold; what is not chained at all (no hash) is counted apart, and the number of version 1 events too.
class Accounting::AuditVerifier
  Result = Struct.new(:count, :broken_id, :version_1, :unchained, keyword_init: true) do
    def intact? = broken_id.nil?
  end

  def self.call(entity:)
    previous = nil
    count = 0
    version_1 = 0
    seen_v2 = false
    scope = Accounting::AuditLog.unscoped.where(entity_id: entity.id)
    scope.where.not(content_hash: nil).order(:id).find_each do |row|
      v2 = row.chain_version == 2
      held = row.previous_hash == previous && row.content_hash == Accounting::AuditLog.digest(row) && (!v2 || row.content_digest == Digest::SHA256.hexdigest(Accounting::AuditLog.content_json(row))) && !(seen_v2 && !v2)
      return Result.new(count: count, broken_id: row.id, version_1: version_1, unchained: unchained(scope)) unless held

      seen_v2 ||= v2
      version_1 += 1 unless v2
      previous = row.content_hash
      count += 1
    end
    Result.new(count: count, broken_id: nil, version_1: version_1, unchained: unchained(scope))
  end

  def self.unchained(scope) = scope.where(content_hash: nil).count
  private_class_method :unchained
end
