# B02c: puts the seal of the instance on the proofs of the clients' decisions: the signature (Ed25519, the key of B03c, which the portal never touches) of the canonical JSON of the proof. Runs
# every minute; a proof waits for a key if there is none. Once sealed, a proof is never sealed again. The firm is told of the decision, with no content.
class PortalAdmin::SealApprovals
  def self.call
    Portal::Approval.where(sealed_at: nil).includes(:publication, :portal_user).order(:id).each { |approval| seal(approval) }
  end

  # What is signed: the evidence and its hash, in canonical JSON.
  def self.message(approval) = LedgerVerify::Canonical.generate({ "type" => "client_approval", "evidence_hash" => approval.evidence_hash, "evidence" => approval.evidence })

  def self.seal(approval)
    key_id, signature = Ledger::SigningKeys.sign(message(approval))
    entity = Entity.find(approval.entity_id)
    ApplicationRecord.transaction do
      approval.update!(seal_key_id: key_id, seal_signature: signature, sealed_at: Time.current)
      ActsAsTenant.with_tenant(entity) do
        Accounting::AuditLog.record!(auditable: approval.publication, action: "portal_publication_decided", actor_type: "portal_user",
                                     payload: { decision: approval.decision, portal_user_id: approval.portal_user_id, evidence_hash: approval.evidence_hash, key_id: key_id })
        Accounting::Notify.call(user: approval.publication.published_by, event: "portal_decision:#{approval.id}", subject: approval.publication,
                                data: { by: approval.portal_user.full_name, message: approval.decision.tr("_", " ") })
      end
    end
  rescue Ledger::SigningKeys::NoActiveKey, Ledger::SigningKeys::PrivateKeyMissing, Ledger::SigningKeys::NotConfigured => e
    Rails.logger.warn("[portal] approval #{approval.id} not sealed yet: #{e.message}")
  end
  private_class_method :seal
end
