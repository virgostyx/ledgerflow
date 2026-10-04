# The reopening of a closed year (F10): an owner (`closing.approve`), with a reason, once the next year is not closed. The locks the closing made (and only those)
# are lifted, the closing entry is taken back (reversed, inside the controlled window of the owner when a lock that is not the closing's still covers its date),
# the year is open again and the next one waits again, the run is `reopened`, and the opening entry of the next year is marked to be recalculated
# (Closing::Steps::CarryForward). All or nothing; audited with the reason; the owners are told once.
class Closing::Reopen
  def self.call(run:, user:, reason:)
    ctx = LightService::Context.make(run: run)
    return ctx.tap { |c| c.fail!("Only an owner can reopen a closed year.") } unless UserEntity.find_by(user: user, entity: run.entity)&.allows?("closing.approve")
    return ctx.tap { |c| c.fail!("A reason is needed to reopen a closed year.") } if reason.to_s.strip.blank?
    return ctx.tap { |c| c.fail!("Only a closed closing can be reopened.") } unless run.closed?

    fiscal_year = run.fiscal_year
    following = Accounting::FiscalYear.find_by(start_date: fiscal_year.end_date + 1)
    return ctx.tap { |c| c.fail!("The next fiscal year is already closed: reopen it first.") } if following&.closed?

    reopened = false
    ApplicationRecord.transaction do
      Accounting::PeriodLock.serialize_for_entity!
      unlock(run, user, reason)
      following&.update!(status: :pre_closing) # only one year is open at a time: the next one waits again, then this one opens
      fiscal_year.update!(status: :open, closed_at: nil, closed_by_id: nil)
      problem = take_back_closing_entry(run, user, reason)
      next ctx.fail!(problem) && raise(ActiveRecord::Rollback) if problem

      run.update!(status: :reopened, reopened_by: user, reopened_at: Time.current, reopen_reason: reason.to_s.strip, carry_forward_stale: true)
      Accounting::AuditLog.record!(auditable: run, action: "closing_reopened", user: user, reason: reason.to_s.strip, payload: { fiscal_year: fiscal_year.year })
      reopened = true
    end
    notify_owners(run) if reopened
    ctx
  end

  # The locks of the closing of this run (by the reason they carry), and no other.
  def self.unlock(run, user, reason)
    marker = Closing::Steps::LockAndBundle.new(run).lock_reason
    Accounting::PeriodLock.where(status: :locked, lock_reason: marker).find_each do |lock|
      result = Accounting::UnlockPeriod.call(lock: lock, user: user, reason: reason.to_s.strip, notify: false)
      raise ActiveRecord::Rollback, result.message if result.failure?
    end
  end
  private_class_method :unlock

  # Reverses the closing entry on its own date. A lock that is not the closing's (a filed VAT period) needs the controlled window.
  def self.take_back_closing_entry(run, user, reason)
    entry = Accounting::JournalEntry.find_by(closing_run_id: run.id, source_type: Accounting::JournalEntry::CLOSING_SOURCE, status: :posted)
    return unless entry

    reverse = proc do
      Accounting::ReverseJournalEntry.call(entry: entry, from_source: true, user: user, date: entry.entry_date, reason: "Reopening of #{run.fiscal_year.year}: #{reason.to_s.strip}")
    end
    result = if Accounting::PeriodLock.covering(entry.entry_date).exists?
      begin
        Accounting::ControlledWindow.within(purpose: "closing", &reverse)
      rescue Accounting::ControlledWindow::Closed
        return "A lock still covers the closing entry: an owner must open a controlled window for the closing (Settings > Periods) before the year can be reopened."
      end
    else
      reverse.call
    end
    result.failure? ? result.message : nil
  end
  private_class_method :take_back_closing_entry

  def self.notify_owners(run)
    User.where(id: UserEntity.current.admin.where(entity_id: run.entity_id).select(:user_id)).find_each { |owner| Accounting::ClosingMailer.reopened(owner, run).deliver_later }
  end
  private_class_method :notify_owners
end
