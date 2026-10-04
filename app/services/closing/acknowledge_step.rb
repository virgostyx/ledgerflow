# A person goes on in spite of a warning (F10): the step stays in warning, acknowledged with a comment. Evaluating again keeps it so while the warning is
# still a warning, and asks again if it turns into a block.
class Closing::AcknowledgeStep
  def self.call(step:, user:, comment:)
    ctx = LightService::Context.make(step: step)
    return ctx.tap { |c| c.fail!("This closing is not open any more.") } unless open?(step)
    return ctx.tap { |c| c.fail!("Only a step in warning can be acknowledged.") } unless step.warning?
    return ctx.tap { |c| c.fail!("A comment is needed to go on in spite of a warning.") } if comment.to_s.strip.blank?

    step.update!(acknowledged_by: user, acknowledged_at: Time.current, comment: comment.to_s.strip)
    ctx
  end

  def self.open?(step) = step.run.draft? || step.run.in_progress? || step.run.ready?
  private_class_method :open?
end
