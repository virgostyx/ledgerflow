class Accounting::PostJournalEntry
  extend LightService::Organizer

  def self.call(entry:)
    result = nil
    ApplicationRecord.transaction do
      result = with(entry: entry).reduce(
        Accounting::Actions::ValidateBalance,
        Accounting::Actions::AssignSequenceNumber,
        Accounting::Actions::LockEntry,
        Accounting::Actions::UpdateAccountBalances,
        Accounting::Actions::WriteAuditLog,
        Accounting::Actions::BroadcastTurboUpdate
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    ctx = LightService::Context.make(entry: entry)
    ctx.fail!("Error: #{e.message}")
    ctx
  end
end
