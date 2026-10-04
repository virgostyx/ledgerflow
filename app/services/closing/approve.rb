# The approval that closes the year (F10, step 18): an owner (`closing.approve`), with a comment, once every blocking step before it is settled. With `four_eyes`, not
# a person who prepared the closing (who opened the run or did one of its steps). The run closes, the year closes, and the next year, which waited, opens.
class Closing::Approve
  def self.call(run:, user:, comment:)
    ctx = LightService::Context.make(run: run)
    membership = UserEntity.find_by(user: user, entity: run.entity)
    return ctx.tap { |c| c.fail!("Only an owner can approve a closing.") } unless membership&.allows?("closing.approve")
    return ctx.tap { |c| c.fail!("This closing is not open any more.") } unless run.draft? || run.in_progress? || run.ready?
    return ctx.tap { |c| c.fail!("A comment is needed to approve a closing.") } if comment.to_s.strip.blank?
    return ctx.tap { |c| c.fail!("With four eyes, the person who prepared the closing cannot approve it.") } if run.entity.four_eyes? && preparers(run).include?(user.id)

    Closing::Evaluate.call(run: run)
    unsettled = run.steps.reload.select { |s| s.blocking && s.code != "approval" && !s.settled? }
    return ctx.tap { |c| c.fail!("These blocking steps are not settled: #{unsettled.map { |s| "#{s.position}. #{s.title}" }.join(', ')}.") } if unsettled.any?

    ApplicationRecord.transaction do
      now = Time.current
      run.steps.find_by!(code: "approval").update!(status: :done, comment: comment.to_s.strip, completed_by: user, completed_at: now)
      run.update!(status: :closed, approved_by: user, approved_at: now, closed_by: user, closed_at: now)
      run.fiscal_year.update!(status: :closed, closed_at: now, closed_by_id: user.id)
      Accounting::FiscalYear.where(start_date: run.fiscal_year.end_date + 1, status: :pre_closing).find_each { |following| following.update!(status: :open) }
      Accounting::AuditLog.record!(auditable: run, action: "closing_approved", user: user, payload: { fiscal_year: run.fiscal_year.year, comment: comment.to_s.strip })
    end
    ctx
  end

  # Who prepared the closing: whoever opened the run, and whoever did one of its steps.
  def self.preparers(run) = [ run.opened_by_id, *run.steps.map(&:completed_by_id) ].compact.uniq
  private_class_method :preparers
end
