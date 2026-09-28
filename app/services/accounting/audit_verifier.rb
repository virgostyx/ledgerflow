# Recomputes the audit chain of an entity (R18): every hashed row must carry the hash of its predecessor and
# the SHA-256 of its own content. Returns the length checked, or the id of the first row that does not hold.
class Accounting::AuditVerifier
  Result = Struct.new(:count, :broken_id, keyword_init: true) do
    def intact? = broken_id.nil?
  end

  def self.call(entity:)
    previous = nil
    count = 0
    Accounting::AuditLog.unscoped.where(entity_id: entity.id).where.not(content_hash: nil).order(:id).find_each do |row|
      return Result.new(count: count, broken_id: row.id) unless row.previous_hash == previous && row.content_hash == Accounting::AuditLog.digest(row)

      previous = row.content_hash
      count += 1
    end
    Result.new(count: count, broken_id: nil)
  end
end
