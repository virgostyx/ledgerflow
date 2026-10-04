# F07: gives up the next due date of a recurring entry (a person's decision: the rent of that month was booked by hand, the period is locked
# for good). A run is kept as "skipped" and the schedule moves on; it does not count as an occurrence.
class Accounting::SkipRecurringOccurrence
  def self.call(recurring:, user:)
    ctx = LightService::Context.make(recurring: recurring)
    recurring.with_lock do
      due_on = recurring.next_due_on
      run = Accounting::RecurringRun.find_or_initialize_by(recurring_entry_id: recurring.id, due_on: due_on) { |r| r.recurring_name = recurring.name }
      return ctx.tap { |c| c.fail!("This due date was already made") } if run.persisted? && run.generated?

      run.update!(status: :skipped, error: nil)
      following = recurring.following(due_on)
      finished = recurring.ends_on && following > recurring.ends_on
      recurring.update_columns(next_due_on: following, status: Accounting::RecurringEntry.statuses[finished ? :finished : :active], blocked_reason: nil, updated_at: Time.current)
      Accounting::AuditLog.record!(auditable: recurring, action: "recurring_skipped", user: user, payload: { due_on: due_on.to_s })
    end
    ctx
  end
end
