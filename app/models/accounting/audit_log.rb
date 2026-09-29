class Accounting::AuditLog < ApplicationRecord
  self.table_name = "accounting_audit_logs"

  belongs_to :user, optional: true

  validates :auditable_type, presence: true
  validates :auditable_id,   presence: true
  validates :action,         presence: true

  scope :for_record,  ->(record)  { where(auditable_type: record.class.name, auditable_id: record.id) }
  scope :for_action,  ->(action)  { where(action: action) }
  scope :chronologic, -> { order(created_at: :asc) }

  # Appends an entry to the entity's hash chain. The advisory lock serializes writers per entity so two
  # concurrent entries can never share a predecessor. Request context defaults come from `Current`.
  def self.record!(auditable:, action:, user: nil, payload: {}, ip_address: nil, reason: nil)
    user ||= Current.user
    entity_id = ActsAsTenant.current_tenant&.id
    # Third-party writes have no user: the calling application goes into the (hashed) payload instead.
    payload = payload.merge(api_client: { id: Current.api_client.id, name: Current.api_client.name }) if Current.api_client
    connection.transaction do
      connection.execute("SELECT pg_advisory_xact_lock(hashtext('accounting_audit_logs'), #{entity_id.to_i})")
      previous = unscoped.where(entity_id: entity_id).where.not(content_hash: nil).order(id: :desc).pick(:content_hash)
      entry = new(
        auditable_type: auditable.class.name, auditable_id: auditable.id, action: action,
        user_id: user&.id, user_email: user&.email, payload: payload, entity_id: entity_id,
        ip_address: ip_address || Current.ip_address, user_agent: Current.user_agent, request_id: Current.request_id,
        reason: reason || Current.reason, previous_hash: previous, created_at: Time.current.utc.round(6)
      )
      entry.content_hash = digest(entry)
      entry.save!
      entry
    end
  end

  # SHA-256(previous hash + canonical content). Keys sorted recursively, values as JSON: the same string
  # is rebuilt from the stored row, whatever order Postgres returns the jsonb keys in.
  def self.digest(entry)
    content = {
      auditable_type: entry.auditable_type, auditable_id: entry.auditable_id, action: entry.action, user_id: entry.user_id,
      user_email: entry.user_email, payload: entry.payload, ip_address: entry.ip_address, reason: entry.reason,
      request_id: entry.request_id, user_agent: entry.user_agent, entity_id: entry.entity_id,
      created_at: entry.created_at.utc.iso8601(6)
    }
    Digest::SHA256.hexdigest("#{entry.previous_hash}#{JSON.generate(canonical(content.as_json))}")
  end

  def self.canonical(value)
    case value
    when Hash then value.sort.to_h { |k, v| [ k.to_s, canonical(v) ] }
    when Array then value.map { |v| canonical(v) }
    else value
    end
  end
end
