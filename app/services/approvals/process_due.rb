# What time does to the requests that wait (B01a §4 "Délais, escalade et absence"), run every hour for every entity that has the
# feature: reminders after the hours of the policy (one per run at most, never a burst), escalation when the service time of the
# level is over (the person named, else the owners), rerouting to the owners when nobody named can decide any more.
# Everything is told once (the notification key) and written in the audit trail.
class Approvals::ProcessDue
  def self.call
    Entity.find_each do |entity|
      next unless entity.feature?(:b01a)

      ActsAsTenant.with_tenant(entity) { new.process }
    end
  end

  def process
    Approvals::Request.pending.includes(:policy, :subject).find_each do |request|
      step = request.policy&.steps&.find_by(position: request.current_step)
      next unless step && request.step_started_at

      reroute(request) if request.rerouted_at.nil? && Approvals::Approvers.for(request).empty?
      remind(request, step)
      escalate(request, step)
    end
  end

  private

  def hours_waiting(request) = (Time.current - request.step_started_at) / 1.hour

  def remind(request, step)
    due = request.policy.reminder_hours.count { |hours| hours <= hours_waiting(request) }
    return unless due > request.reminders_sent

    request.update!(reminders_sent: due)
    tell(Approvals::Approvers.for(request).keys, "approval_reminder:#{request.id}:#{step.position}:#{due}", request)
    audit(request, "approval_reminder", step: step.position, number: due)
  end

  def escalate(request, step)
    return if request.escalated_at || step.service_hours.nil? || hours_waiting(request) < step.service_hours

    target = step.escalate_to if step.escalate_to && can_approve?(step.escalate_to)
    request.update!(escalated_at: Time.current, escalated_to_id: target&.id)
    tell(target ? [ target.id ] : owner_ids, "approval_escalated:#{request.id}:#{step.position}", request)
    audit(request, "approval_escalated", step: step.position, escalated_to: target&.id || "owners")
  end

  def reroute(request)
    request.update!(rerouted_at: Time.current)
    tell(owner_ids, "approval_rerouted:#{request.id}:#{request.current_step}", request)
    audit(request, "approval_rerouted", step: request.current_step)
  end

  def tell(user_ids, event, request)
    User.where(id: user_ids).find_each { |user| Accounting::Notify.call(user: user, event: event, subject: request) }
  end

  def audit(request, action, payload)
    Accounting::AuditLog.record!(auditable: request.subject, action: action, payload: payload.merge(request_id: request.id))
  end

  def owner_ids = UserEntity.owners.current.pluck(:user_id)

  def can_approve?(user)
    UserEntity.current.find_by(user_id: user.id)&.allows?("approvals.approve") == true
  end
end
