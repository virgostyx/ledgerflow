# B03b: marks a change as reviewed. Who may is decided by the caller (`changes.review`); the mark is in the audit trail (R18).
class Changes::Review
  def self.call(key:, user:, comment: nil)
    ctx = LightService::Context.make(review: nil)
    ApplicationRecord.transaction do
      review = Accounting::ChangeReview.create!(change_key: key, reviewer: user, reviewed_at: Time.current, comment: comment.presence)
      Accounting::AuditLog.record!(auditable: review, action: "change_reviewed", user: user, reason: comment.presence, payload: { change_key: key })
      ctx[:review] = review
    end
    ctx
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    ctx.fail!(I18n.t("changes.errors.already_reviewed"))
    ctx
  end

  # { change_key => review } for those of `keys` that were reviewed.
  def self.reviewed(keys) = Accounting::ChangeReview.where(change_key: keys).includes(:reviewer).index_by(&:change_key)
end
