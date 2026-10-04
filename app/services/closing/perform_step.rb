# Does the work of an action step of an open run (F10), for someone who may prepare a closing (`closing.prepare`), and records who did it. The step does its work
# idempotently; the run is read again afterwards. Extra arguments go to the step. => ctx of the step
class Closing::PerformStep
  def self.call(run:, code:, user:, **params)
    return LightService::Context.make.tap { |c| c.fail!("You are not allowed to run the closing.") } unless UserEntity.find_by(user: user, entity: run.entity)&.allows?("closing.prepare")
    return LightService::Context.make.tap { |c| c.fail!("This closing is not open any more.") } unless run.draft? || run.in_progress? || run.ready?

    row = run.steps.find_by(code: code)
    step = Closing::Registry.fetch(code)&.new(run)
    return LightService::Context.make.tap { |c| c.fail!("Only an action step does something.") } unless row&.kind_action? && step

    result = step.perform(user: user, **params)
    row.update!(completed_by: user, completed_at: Time.current) if result.success?
    Closing::Evaluate.call(run: run)
    result
  end
end
