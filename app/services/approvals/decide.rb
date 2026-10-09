# One decision on a request (B01a): approve, refuse (reason required) or ask for changes (reason required, a task for the author).
# The decision carries the fingerprint of the content the person had in front of them: it must still be the request's, and the invoice's.
# Separation of tasks: the author of an invoice does not approve it, nor does a delegate for the author or for themselves,
# unless the entity allows self-approval. Nobody decides twice on a level.
# => ctx[:decision]
class Approvals::Decide
  DECISIONS = %w[approved rejected changes_requested].freeze

  def self.call(request:, user:, decision:, content_fingerprint:, comment: nil, channel: :web, device_fingerprint: nil)
    ctx = LightService::Context.make(decision: nil)
    invoice = request.subject
    refusal = refusal_for(request, invoice, user, decision.to_s, content_fingerprint, comment)
    return ctx.tap { |c| c.fail!(refusal) } if refusal

    ApplicationRecord.transaction do
      request.lock!
      next ctx.fail!(I18n.t("approvals.errors.not_pending")) unless request.pending? # lost a race with another click

      on_behalf_of = Approvals::Approvers.for(request)[user.id]
      ctx[:decision] = request.decisions.create!(step_position: request.current_step, approver: user, on_behalf_of_id: on_behalf_of, decision: decision,
                                                 comment: comment, channel: channel, device_fingerprint: device_fingerprint, content_fingerprint: content_fingerprint)
      apply(request, invoice, ctx[:decision], user)
    end
    ctx
  end

  def self.refusal_for(request, invoice, user, decision, content_fingerprint, comment)
    return I18n.t("approvals.errors.feature_off") unless invoice.entity.feature?(:b01a)
    return I18n.t("approvals.errors.not_pending") unless request.pending?
    return I18n.t("approvals.errors.unknown_decision") unless DECISIONS.include?(decision)
    return I18n.t("approvals.errors.reason_required") if decision != "approved" && comment.blank?
    return I18n.t("approvals.errors.content_changed") unless content_fingerprint == request.content_fingerprint && Approvals::ContentFingerprint.call(invoice) == request.content_fingerprint

    approvers = Approvals::Approvers.for(request)
    return I18n.t("approvals.errors.not_an_approver") unless approvers.key?(user.id)

    on_behalf_of = approvers[user.id]
    return I18n.t("approvals.errors.own_entry") if own_entry?(invoice, user, on_behalf_of)
    I18n.t("approvals.errors.already_decided") if already_decided?(request, user, on_behalf_of)
  end
  private_class_method :refusal_for

  def self.own_entry?(invoice, user, on_behalf_of)
    return false if invoice.entity.allow_self_approval?

    [ user.id, on_behalf_of ].compact.include?(invoice.created_by_id)
  end
  private_class_method :own_entry?

  def self.already_decided?(request, user, on_behalf_of)
    request.decisions.where(step_position: request.current_step, approver_id: user.id).or(
      request.decisions.where(step_position: request.current_step, approver_id: on_behalf_of)
    ).or(request.decisions.where(step_position: request.current_step, on_behalf_of_id: user.id)).exists?
  end
  private_class_method :already_decided?

  def self.apply(request, invoice, decision, user)
    payload = { request_id: request.id, step: decision.step_position, channel: decision.channel, on_behalf_of: decision.on_behalf_of_id,
                content_fingerprint: decision.content_fingerprint, device_fingerprint: decision.device_fingerprint }
    case decision.decision
    when "approved" then approve(request, invoice)
    when "rejected" then close(request, invoice, :rejected)
    when "changes_requested" then ask_for_changes(request, invoice, decision, user)
    end
    Accounting::AuditLog.record!(auditable: invoice, action: "approval_#{decision.decision}", user: user, payload: payload, reason: decision.comment)
  end
  private_class_method :apply

  def self.approve(request, invoice)
    return unless level_complete?(request)

    following = request.policy.steps.where("position > ?", request.current_step).first
    if following
      request.update!(current_step: following.position, step_started_at: Time.current)
    else
      request.update!(status: :approved, decided_at: Time.current)
      invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[:approved])
    end
  end
  private_class_method :approve

  # any_of: one approval is enough. all_of: every person named has approved, and every role named is represented.
  def self.level_complete?(request)
    step = request.policy.steps.find_by!(position: request.current_step)
    approved = request.decisions.approved.where(step_position: step.position)
    return approved.exists? if step.any_of?

    principals = approved.map { |d| d.on_behalf_of_id || d.approver_id }
    roles = UserEntity.current.where(user_id: principals).pluck(:role)
    step.approver_user_ids.all? { |id| principals.include?(id) } && step.approver_roles.all? { |role| roles.include?(role) }
  end
  private_class_method :level_complete?

  def self.close(request, invoice, status)
    request.update!(status: status, decided_at: Time.current)
    invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[:on_hold])
  end
  private_class_method :close

  def self.ask_for_changes(request, invoice, decision, user)
    close(request, invoice, :changes_requested)
    assignee = invoice.created_by || request.submitted_by
    task = Accounting::Task.create!(title: I18n.t("approvals.task.title", number: invoice.invoice_number || invoice.id), description: decision.comment, kind: :to_check,
                                    priority: :high, assignee: assignee, author: user, target: invoice)
    Accounting::Notify.call(user: assignee, event: "task_assigned", subject: task, data: { by: user.full_name }) if assignee && assignee != user
  end
  private_class_method :ask_for_changes
end
