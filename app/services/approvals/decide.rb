# One decision on a request (B01a): approve, refuse (reason required), ask for changes (reason required, a task for the author) or hand the request to another
# approver (who then decides in the name of the one who handed it over, for this level only).
# The decision carries the fingerprint of the content the person had in front of them: it must still be the request's, and the invoice's.
# Separation of tasks: the author of an invoice does not approve it, nor does a delegate for the author or for themselves,
# unless the entity allows self-approval. Nobody decides twice on a level.
# => ctx[:decision]
class Approvals::Decide
  DECISIONS = %w[approved rejected changes_requested transferred].freeze

  def self.call(request:, user:, decision:, content_fingerprint:, comment: nil, channel: :web, device_fingerprint: nil, recent_second_factor: false, transfer_to_id: nil)
    ctx = LightService::Context.make(decision: nil)
    invoice = request.subject
    directory = Approvals::Directory.new(invoice.entity) # who is who in this entity, read once
    code = refusal_for(request, invoice, user, decision.to_s, content_fingerprint, comment, recent_second_factor, directory, transfer_to_id)
    return refuse(ctx, code) if code

    ApplicationRecord.transaction do
      request.lock!
      next refuse(ctx, :not_pending) unless request.pending? # lost a race with another click

      on_behalf_of = Approvals::Approvers.for(request, directory)[user.id]
      ctx[:decision] = request.decisions.create!(step_position: request.current_step, approver: user, on_behalf_of_id: on_behalf_of, decision: decision,
                                                 comment: comment, channel: channel, device_fingerprint: device_fingerprint, content_fingerprint: content_fingerprint,
                                                 transferred_to_id: (transfer_to_id if decision.to_s == "transferred"))
      apply(request, invoice, ctx[:decision], user, directory)
    end
    ctx
  end

  # The refusal as a code (callers answer by kind) and as the sentence the screens show.
  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("approvals.errors.#{code}"))
    ctx
  end
  private_class_method :refuse

  def self.refusal_for(request, invoice, user, decision, content_fingerprint, comment, recent_second_factor, directory, transfer_to_id)
    return :feature_off unless invoice.entity.feature?(:b01a)
    return :content_changed if request.invalidated? # the invoice changed after the approver opened it
    return :not_pending unless request.pending?
    return :unknown_decision unless DECISIONS.include?(decision)
    return :reason_required if %w[rejected changes_requested].include?(decision) && comment.blank?
    return :content_changed unless content_fingerprint == request.content_fingerprint && Approvals::ContentFingerprint.call(invoice) == request.content_fingerprint

    approvers = Approvals::Approvers.for(request, directory)
    return :not_an_approver unless approvers.key?(user.id)

    on_behalf_of = approvers[user.id]
    return :own_entry if own_entry?(invoice, user, on_behalf_of)
    return :already_decided if already_decided?(request, user, on_behalf_of)
    return :invalid_transfer if decision == "transferred" && !valid_transfer?(transfer_to_id, user, directory)

    :step_up_required if decision == "approved" && !recent_second_factor && step_up?(invoice)
  end
  private_class_method :refusal_for

  # Above the threshold of the entity (incl. VAT, in EUR; the threshold itself is allowed), approving asks for a second factor given a moment ago.
  def self.step_up?(invoice)
    threshold = invoice.entity.step_up_threshold
    threshold.present? && Approvals::Amount.eur(invoice) > threshold
  end
  private_class_method :step_up?

  # Another person of this entity, who can approve here.
  def self.valid_transfer?(transfer_to_id, user, directory)
    transfer_to_id.present? && transfer_to_id != user.id && directory.approving?(transfer_to_id)
  end
  private_class_method :valid_transfer?

  def self.own_entry?(invoice, user, on_behalf_of)
    return false if invoice.entity.allow_self_approval?

    [ user.id, on_behalf_of ].compact.include?(invoice.created_by_id)
  end
  private_class_method :own_entry?

  # Nobody decides twice on a level. Whoever handed the request over has decided (they cannot decide any more), but their having handed it over
  # does not stop the one they handed it to from deciding in their name.
  def self.already_decided?(request, user, on_behalf_of)
    here = request.decisions.where(step_position: request.current_step)
    decided = here.where.not(decision: :transferred)
    here.exists?(approver_id: user.id) || decided.exists?(approver_id: on_behalf_of) || decided.exists?(on_behalf_of_id: user.id)
  end
  private_class_method :already_decided?

  def self.apply(request, invoice, decision, user, directory)
    payload = { request_id: request.id, step: decision.step_position, transferred_to: decision.transferred_to_id, channel: decision.channel, on_behalf_of: decision.on_behalf_of_id,
                content_fingerprint: decision.content_fingerprint, device_fingerprint: decision.device_fingerprint }
    case decision.decision
    when "approved" then approve(request, invoice, directory)
    when "rejected" then close(request, invoice, :rejected)
    when "changes_requested" then ask_for_changes(request, invoice, decision, user, directory)
    when "transferred" then hand_over(request, decision, user)
    end
    Accounting::AuditLog.record!(auditable: invoice, action: "approval_#{decision.decision}", user: user, payload: payload, reason: decision.comment)
  end
  private_class_method :apply

  def self.approve(request, invoice, directory)
    return unless level_complete?(request, directory)

    following = request.policy.steps.where("position > ?", request.current_step).first
    if following
      request.update!(current_step: following.position, step_started_at: Time.current, reminders_sent: 0, escalated_at: nil, escalated_to_id: nil, rerouted_at: nil, transfers: {})
    else
      request.update!(status: :approved, decided_at: Time.current)
      invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[:approved])
    end
  end
  private_class_method :approve

  # any_of: one approval is enough. all_of: every person named has approved, and every role named is represented.
  def self.level_complete?(request, directory)
    step = request.policy.steps.find_by!(position: request.current_step)
    approved = request.decisions.approved.where(step_position: step.position)
    return approved.exists? if step.any_of?

    principals = approved.map { |d| d.on_behalf_of_id || d.approver_id }
    roles = principals.filter_map { |id| directory.role_of(id) }
    step.approver_user_ids.all? { |id| principals.include?(id) } && step.approver_roles.all? { |role| roles.include?(role) }
  end
  private_class_method :level_complete?

  # The other person may now decide on this level, in the name of the one who handed over (or of whoever that one was standing in for).
  def self.hand_over(request, decision, user)
    request.update!(transfers: request.transfers.merge(decision.transferred_to_id.to_s => decision.on_behalf_of_id || user.id))
    Accounting::Notify.call(user: decision.transferred_to, event: "approval_transferred:#{request.id}:#{decision.step_position}", subject: request)
  end
  private_class_method :hand_over

  def self.close(request, invoice, status)
    request.update!(status: status, decided_at: Time.current)
    invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[:on_hold])
  end
  private_class_method :close

  def self.ask_for_changes(request, invoice, decision, user, directory)
    close(request, invoice, :changes_requested)
    # whoever wrote it, else whoever submitted it, as long as they are still of the entity (a task needs a member); otherwise the task waits for an owner to assign it
    assignee = User.find_by(id: [ invoice.created_by_id, request.submitted_by_id ].compact.find { |id| directory.member?(id) })
    task = Accounting::Task.create!(title: I18n.t("approvals.task.title", number: invoice.invoice_number || invoice.id), description: decision.comment, kind: :to_check,
                                    priority: :high, assignee: assignee, author: user, target: invoice)
    Accounting::Notify.call(user: assignee, event: "task_assigned", subject: task, data: { by: user.full_name }) if assignee && assignee != user
  end
  private_class_method :ask_for_changes
end
