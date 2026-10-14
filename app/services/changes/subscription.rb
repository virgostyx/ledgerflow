# B03b: subscribes a person to the alerts that matter to them, or ends it (no kind left). Who may is decided by the caller (`changes.review`); each action is in the audit trail.
module Changes::Subscription
  def self.set(user:, kinds:)
    kinds = Array(kinds).map(&:to_s) & Accounting::ChangeSubscription::KINDS
    ctx = LightService::Context.make
    ApplicationRecord.transaction do
      subscription = Accounting::ChangeSubscription.find_or_initialize_by(user_id: user.id)
      before = subscription.kinds
      if kinds.empty?
        subscription.destroy! if subscription.persisted?
      else
        subscription.update!(kinds: kinds)
      end
      Accounting::AuditLog.record!(auditable: ActsAsTenant.current_tenant, action: "change_subscription_changed", user: user, payload: { from: before, to: kinds })
    end
    ctx
  end
end
