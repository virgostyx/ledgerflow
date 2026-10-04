# F07: makes the entries of the recurring entries of the current entity that have come due (the due date less the lead days is reached). Run
# every day by Accounting::GenerateRecurringEntriesJob and idempotent: one run per recurring entry and due date (unique key), the recurring
# entry locked while it is worked on. After an interruption the missed due dates are made up, 12 at most per run, the owners told of the
# rest. A due date in a locked period, or whose template cannot be used (archived account), makes nothing, blocks the recurring entry with
# the reason and tells the owners once; it is tried again at every run, so it carries on by itself when the cause is gone.
# => number of entries made
class Accounting::GenerateRecurringEntries
  CATCH_UP_LIMIT = 12

  def self.call(today: Date.current)
    Accounting::RecurringEntry.due_by(today).order(:id).to_a.sum { |recurring| new(recurring, today).call }
  end

  def initialize(recurring, today)
    @recurring = recurring
    @today = today
  end

  def call
    made = 0
    @recurring.with_lock do
      @recurring.reload
      while due_now? && made < CATCH_UP_LIMIT
        outcome = run(@recurring.next_due_on)
        return made if outcome == :blocked

        made += 1 if outcome == :generated
      end
      tell_backlog if due_now?
    end
    made
  end

  private

  def due_now? = (@recurring.active? || @recurring.blocked?) && @recurring.next_due_on - @recurring.lead_days <= @today

  # => :generated, :already (made by someone else), :blocked
  def run(due_on)
    run = Accounting::RecurringRun.find_or_initialize_by(recurring_entry_id: @recurring.id, due_on: due_on) { |r| r.recurring_name = @recurring.name }
    return advance(due_on, :already) if run.persisted? && (run.generated? || run.skipped?)

    reason = obstacle(due_on)
    return block(run, reason) if reason

    index_amount(due_on)
    result = Accounting::BuildEntryFromTemplate.call(template: @recurring.entry_template, date: due_on, base_amount: @recurring.base_amount, user: nil)
    return block(run, result.message) if result.failure?

    entry = result[:entry]
    if @recurring.mode_post?
      posted = Accounting::PostJournalEntry.call(entry: entry)
      return block(run, posted.message) if posted.failure?
    end
    run.update!(journal_entry: entry, status: :generated, amount: entry.lines.sum(:debit), error: nil)
    Accounting::AuditLog.record!(auditable: @recurring, action: "recurring_generated", user: nil, payload: { entry_id: entry.id, due_on: due_on.to_s, posted: @recurring.mode_post? })
    advance(due_on, :generated)
  rescue ActiveRecord::RecordNotUnique
    advance(due_on, :already)
  end

  def obstacle(due_on)
    lock = Accounting::PeriodLock.covering(due_on).first
    I18n.t("accounting.recurring.errors.locked_period", date: I18n.l(due_on), from: I18n.l(lock.starts_on), to: I18n.l(lock.ends_on)) if lock
  end

  def block(run, reason)
    run.update!(status: :blocked, error: reason)
    newly = !@recurring.blocked? || @recurring.blocked_reason != reason
    @recurring.update_columns(status: Accounting::RecurringEntry.statuses[:blocked], blocked_reason: reason, updated_at: Time.current)
    if newly
      Accounting::AuditLog.record!(auditable: @recurring, action: "recurring_blocked", user: nil, payload: { due_on: run.due_on.to_s, reason: reason })
      owners.each { |owner| Accounting::RecurringMailer.blocked(owner, @recurring, reason).deliver_later }
    end
    :blocked
  end

  # The first occurrence of each calendar year after the first one raises the amount by the percentage (rounded to the cent). A year skipped by an
  # interruption is applied in turn. The old and the new amounts are kept in the audit trail.
  def index_amount(due_on)
    percent = @recurring.indexation_percent
    return if percent.blank? || percent.zero?

    year = @recurring.indexed_year || @recurring.starts_on.year
    while year < due_on.year
      year += 1
      old_amount = @recurring.base_amount
      new_amount = (old_amount * (1 + percent / 100)).round(2, half: :up)
      @recurring.update_columns(base_amount: new_amount, indexed_year: year, updated_at: Time.current)
      Accounting::AuditLog.record!(auditable: @recurring, action: "recurring_indexed", user: nil,
                                   payload: { year: year, percent: percent.to_s, old_amount: old_amount.to_s, new_amount: new_amount.to_s })
    end
  end

  def advance(due_on, outcome)
    count = @recurring.occurrences_count + (outcome == :generated ? 1 : 0)
    following = @recurring.following(due_on)
    finished = (@recurring.max_occurrences && count >= @recurring.max_occurrences) || (@recurring.ends_on && following > @recurring.ends_on)
    @recurring.update_columns(occurrences_count: count, next_due_on: following, status: Accounting::RecurringEntry.statuses[finished ? :finished : :active],
                              blocked_reason: nil, updated_at: Time.current)
    outcome
  end

  def tell_backlog
    owners.each { |owner| Accounting::RecurringMailer.backlog(owner, @recurring).deliver_later }
  end

  def owners = User.where(id: UserEntity.current.admin.where(entity_id: @recurring.entity_id).select(:user_id)).to_a
end
