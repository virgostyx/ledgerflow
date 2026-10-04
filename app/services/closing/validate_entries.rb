# The batch validation of the closing entries (F10): the drafts the steps made (the closing entry, the opening entry of the next year) are posted by a person who
# may post (`entries.post`), after the preview of their lines. When a lock covers the date of one of them (the VAT periods are locked by step 5), it is done
# inside the controlled window of the closing that an owner opened (F01); without it, nothing is posted. All or nothing. => ctx[:posted]
class Closing::ValidateEntries
  def self.call(run:, user:)
    ctx = LightService::Context.make(posted: [])
    return ctx.tap { |c| c.fail!("You are not allowed to validate entries.") } unless UserEntity.find_by(user: user, entity: run.entity)&.allows?("entries.post")

    drafts = Accounting::JournalEntry.where(closing_run_id: run.id, status: :draft).order(:entry_date, :id).to_a
    return ctx.tap { |c| c.fail!("There is no closing entry to validate.") } if drafts.empty?

    posting = proc { post_all(run, user, drafts, ctx) }
    if drafts.any? { |entry| Accounting::PeriodLock.covering(entry.entry_date).exists? }
      begin
        Accounting::ControlledWindow.within(purpose: "closing", &posting)
      rescue Accounting::ControlledWindow::Closed
        ctx.fail!("A lock covers the closing entries: an owner must open a controlled window for the closing (Settings > Periods) before they can be validated.")
      end
    else
      ApplicationRecord.transaction(&posting)
    end
    ctx
  end

  def self.post_all(run, user, drafts, ctx)
    drafts.each do |entry|
      posted = Accounting::PostJournalEntry.call(entry: entry, keep_reference: true)
      if posted.failure?
        ctx.fail!("#{entry.description}: #{posted.message}")
        raise ActiveRecord::Rollback
      end
      ctx[:posted] << entry.reload
    end
    Accounting::AuditLog.record!(auditable: run, action: "closing_entries_validated", user: user, payload: { entries: ctx[:posted].map(&:id) })
  end
  private_class_method :post_all
end
