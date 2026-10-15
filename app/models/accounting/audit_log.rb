require Rails.root.join("tools/ledger-verify/lib/ledger_verify/canonical")

class Accounting::AuditLog < ApplicationRecord
  self.table_name = "accounting_audit_logs"

  # Screens only ever see their own entity's rows. Rows of global reference data (VAT codes) have no entity: record!
  # writes them outside any tenant, with the entity_id it computed itself.
  acts_as_tenant :entity, optional: true
  belongs_to :user, optional: true

  validates :auditable_type, presence: true
  validates :auditable_id,   presence: true
  validates :action,         presence: true

  # Who wrote the row: a person of the firm, or (B02a) someone of the client portal. Hashed into the chain only when it is
  # not a user, so every row written before the column existed keeps its hash.
  ACTOR_TYPES = %w[user portal_user].freeze
  validates :actor_type, inclusion: { in: ACTOR_TYPES }

  scope :for_record,  ->(record)  { where(auditable_type: record.class.name, auditable_id: record.id) }
  scope :for_action,  ->(action)  { where(action: action) }
  scope :chronologic, -> { order(created_at: :asc) }

  # Appends an entry to the entity's hash chain. The advisory lock serializes writers per entity so two
  # concurrent entries can never share a predecessor. Request context defaults come from `Current`.
  # Events are written in version 2 of the chain (B03c); the first one after the chain was in version 1 is preceded by an event that says so.
  def self.record!(auditable:, action:, user: nil, payload: {}, ip_address: nil, reason: nil, actor_type: "user")
    user ||= Current.user
    entity_id = ActsAsTenant.current_tenant&.id
    # Third-party writes have no user: the calling application goes into the (hashed) payload instead.
    payload = payload.merge(api_client: { id: Current.api_client.id, name: Current.api_client.name }) if Current.api_client
    connection.transaction do
      connection.execute("SELECT pg_advisory_xact_lock(hashtext('accounting_audit_logs'), #{entity_id.to_i})")
      head = unscoped.where(entity_id: entity_id).where.not(content_hash: nil).order(id: :desc).first
      head = append_chain_switch(head, entity_id, auditable) if head && head.chain_version.nil?
      previous = head&.content_hash
      entry = ActsAsTenant.without_tenant { new(
        auditable_type: auditable.class.name, auditable_id: auditable.id, action: action,
        user_id: user&.id, user_email: user&.email, payload: payload, entity_id: entity_id,
        ip_address: ip_address || Current.ip_address, user_agent: Current.user_agent, request_id: Current.request_id,
        reason: reason || Current.reason, actor_type: actor_type, previous_hash: previous, created_at: Time.current.utc.round(6)
      ) }
      seal(entry)
      ActsAsTenant.without_tenant { entry.save! }
      entry
    end
  end

  # The event that puts the chain in version 2, on the head of version 1.
  def self.append_chain_switch(head, entity_id, auditable)
    switch = ActsAsTenant.without_tenant { new(auditable_type: auditable.class.name, auditable_id: auditable.id, action: "audit_chain_version_2", entity_id: entity_id, payload: { "from" => 1, "to" => 2, "head" => head.content_hash },
                                               previous_hash: head.content_hash, created_at: Time.current.utc.round(6)) }
    seal(switch)
    ActsAsTenant.without_tenant { switch.save! }
    switch
  end
  private_class_method :append_chain_switch

  def self.seal(entry)
    entry.chain_version = 2
    entry.content_digest = Digest::SHA256.hexdigest(content_json(entry))
    entry.content_hash = digest(entry)
  end
  private_class_method :seal

  # What links the events: version 2, SHA-256(previous hash || content digest || metadata); version 1, SHA-256(previous hash || content), still how the old events are checked.
  def self.digest(entry) = entry.chain_version == 2 ? digest_v2(entry) : digest_v1(entry)

  def self.digest_v2(entry) = Digest::SHA256.hexdigest("#{entry.previous_hash}#{entry.content_digest || Digest::SHA256.hexdigest(content_json(entry))}#{metadata_json(entry)}")

  # The content of an event (everything personal is here), as canonical JSON (RFC 8785): its SHA-256 is the digest a third party keeps.
  def self.content_json(entry)
    content = content_of(entry)
    content[:actor_type] = entry.actor_type unless entry.actor_type == "user"
    LedgerVerify::Canonical.generate(content.as_json)
  end

  # What says when, what and about what, and nothing that says who or from where: the metadata of version 2.
  def self.metadata_json(entry)
    LedgerVerify::Canonical.generate("action" => entry.action, "actor_type" => entry.actor_type, "auditable_id" => entry.auditable_id, "auditable_type" => entry.auditable_type,
                                     "created_at" => entry.created_at.utc.iso8601(6), "entity_id" => entry.entity_id)
  end

  # SHA-256(previous hash + canonical content), version 1: keys sorted recursively, values as JSON, the same string is rebuilt from the stored row, whatever order Postgres
  # returns the jsonb keys in. Not RFC 8785, and kept as it was: the old events are never rewritten.
  def self.digest_v1(entry)
    content = content_of(entry)
    content[:actor_type] = entry.actor_type unless entry.actor_type == "user"
    Digest::SHA256.hexdigest("#{entry.previous_hash}#{JSON.generate(canonical(content.as_json))}")
  end

  def self.content_of(entry)
    {
      auditable_type: entry.auditable_type, auditable_id: entry.auditable_id, action: entry.action, user_id: entry.user_id,
      user_email: entry.user_email, payload: entry.payload, ip_address: entry.ip_address, reason: entry.reason,
      request_id: entry.request_id, user_agent: entry.user_agent, entity_id: entry.entity_id,
      created_at: entry.created_at.utc.iso8601(6)
    }
  end
  private_class_method :content_of

  def self.canonical(value)
    case value
    when Hash then value.sort.to_h { |k, v| [ k.to_s, canonical(v) ] }
    when Array then value.map { |v| canonical(v) }
    else value
    end
  end
end
