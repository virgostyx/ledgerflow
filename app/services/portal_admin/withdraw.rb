# B02a: hides a publication from the clients and keeps it (and its files) for the audit.
class PortalAdmin::Withdraw
  def self.call(publication:, by:, reason:)
    ApplicationRecord.transaction do
      publication.update!(status: "withdrawn", withdrawn_at: Time.current, withdrawn_by: by, withdrawal_reason: reason)
      ActsAsTenant.with_tenant(Entity.find(publication.entity_id)) do
        Accounting::AuditLog.record!(auditable: publication, action: "portal_withdrawn", user: by, reason: reason, payload: { title: publication.title, version: publication.version })
      end
    end
    LightService::Context.make
  end
end
