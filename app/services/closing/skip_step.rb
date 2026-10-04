# A step that does not block is skipped, with a reason (F10).
class Closing::SkipStep
  def self.call(step:, user:, reason:)
    ctx = LightService::Context.make(step: step)
    return ctx.tap { |c| c.fail!("This closing is not open any more.") } unless step.run.draft? || step.run.in_progress? || step.run.ready?
    return ctx.tap { |c| c.fail!("A step that blocks cannot be skipped.") } if step.blocking
    return ctx.tap { |c| c.fail!("A reason is needed to skip a step.") } if reason.to_s.strip.blank?

    step.update!(status: :skipped, comment: reason.to_s.strip, completed_by: user, completed_at: Time.current)
    ctx
  end
end
