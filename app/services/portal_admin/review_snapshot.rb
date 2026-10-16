# B02c: the firm's say on a snapshot: let it through when the company asked to approve first, write "the accountant's word" (by hand, or a draft from the assistant that a person must approve),
# approve it. A word is shown to the client only once a person approved it; changing it asks for a new approval. Texts are cleaned.
class PortalAdmin::ReviewSnapshot
  SOURCES = %w[human agent_draft].freeze

  def self.publish(snapshot, by:)
    return snapshot unless snapshot.status == "pending_review"

    ActsAsTenant.with_tenant(Entity.find(snapshot.entity_id)) do
      snapshot.update!(status: "published", published_at: Time.current, published_by_id: by.id)
      Accounting::AuditLog.record!(auditable: snapshot, action: "portal_snapshot_published", user: by, payload: { sha256: snapshot.sha256 })
    end
    snapshot
  end

  def self.write_word(snapshot, text:, source:, by:)
    raise ArgumentError, "unknown source" unless SOURCES.include?(source)

    snapshot.update!(accountant_word: Portal::Answer.clean(text).presence, word_source: source, word_approved_at: nil, word_approved_by_id: nil)
    snapshot
  end

  def self.approve_word(snapshot, by:)
    return snapshot if snapshot.accountant_word.blank?

    ActsAsTenant.with_tenant(Entity.find(snapshot.entity_id)) do
      snapshot.update!(word_approved_at: Time.current, word_approved_by_id: by.id)
      Accounting::AuditLog.record!(auditable: snapshot, action: "portal_snapshot_word_approved", user: by, payload: { source: snapshot.word_source })
    end
    snapshot
  end
end
