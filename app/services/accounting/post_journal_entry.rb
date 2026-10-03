class Accounting::PostJournalEntry
  extend LightService::Organizer

  # keep_reference: for the entries the system generates under a reference that identifies them (DEP-ASSET-..., which
  # their own service looks up again); an entry without one is still numbered.
  def self.call(entry:, keep_reference: false)
    result = nil
    ApplicationRecord.transaction do
      result = with(entry: entry, keep_reference: keep_reference).reduce(
        Accounting::Actions::ValidatePeriodOpen,
        Accounting::Actions::ValidateFourEyes,
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

  # For services that generate entries inside their own transaction: a refusal is an exception that rolls it back.
  def self.call!(entry:, keep_reference: false)
    result = call(entry: entry, keep_reference: keep_reference)
    raise Accounting::PostRefused, result.message if result.failure?

    result
  end
end
