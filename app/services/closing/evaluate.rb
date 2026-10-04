# Reads every step of a run as it stands now (F10) and moves the run on. A check is evaluated again whatever it said before; an action is done once its
# effect stands; a manual step, a skipped step and a step a person settled are left as they are. The run is `ready` when every blocking step is settled.
# A run that is closed or reopened is not touched.
class Closing::Evaluate
  STATUS = { ok: :ok, warning: :warning, blocked: :blocked, pending: :pending }.freeze

  def self.call(run:)
    return run unless run.draft? || run.in_progress? || run.ready?

    run.steps.includes(:run).each { |row| read(run, row) }
    run.steps.reset
    run.update!(status: run.steps.select(&:blocking).all?(&:settled?) ? :ready : :in_progress)
    run
  end

  def self.read(run, row)
    return if row.skipped? || (row.kind_manual? && row.done?)
    return if row.kind_manual? && !row.pending?

    step = Closing::Registry.fetch(row.code)&.new(run)
    return unless step

    outcome = step.evaluate
    status = row.kind_action? && outcome.status == :ok ? :done : STATUS.fetch(outcome.status)
    status = :pending if row.kind_manual?
    acknowledged = status == :warning && row.warning? && row.acknowledged_at # still the same warning: the acknowledgement stands
    row.update!(status: status, result: outcome.details, **(acknowledged ? {} : { acknowledged_at: nil, acknowledged_by: nil }))
  end
  private_class_method :read
end
