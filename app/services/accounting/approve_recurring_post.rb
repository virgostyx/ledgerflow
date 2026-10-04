# F07: an owner lets a recurring entry post by itself. Only for a template of known amounts; audited. Any later change of the template or
# of the amount takes the approval back (RecurringEntry#fall_back_to_draft).
class Accounting::ApproveRecurringPost
  def self.call(recurring:, user:)
    ctx = LightService::Context.make(recurring: recurring)
    return ctx.tap { |c| c.fail!(I18n.t("errors.not_authorized")) } unless Accounting::RecurringEntryPolicy.new(user, recurring).approve_post?

    ApplicationRecord.transaction do
      recurring.approving = true
      begin
        recurring.update!(mode: :post, post_approved_by: user, post_approved_at: Time.current)
      ensure
        recurring.approving = false
      end
      Accounting::AuditLog.record!(auditable: recurring, action: "recurring_post_approved", user: user, payload: { base_amount: recurring.base_amount.to_s })
    end
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!(e.message)
  end
end
