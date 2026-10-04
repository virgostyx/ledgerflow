# A manual step is confirmed by a person, with a comment (F10): the stock variation entered, the provisions booked or declared without object, the tax.
class Closing::ConfirmStep
  def self.call(step:, user:, comment:)
    ctx = LightService::Context.make(step: step)
    return ctx.tap { |c| c.fail!("This closing is not open any more.") } unless step.run.draft? || step.run.in_progress? || step.run.ready?
    return ctx.tap { |c| c.fail!("Only a manual step is confirmed by hand.") } unless step.kind_manual?
    return ctx.tap { |c| c.fail!("A comment is needed to confirm a step.") } if comment.to_s.strip.blank?

    step.update!(status: :done, comment: comment.to_s.strip, completed_by: user, completed_at: Time.current)
    ctx
  end
end
