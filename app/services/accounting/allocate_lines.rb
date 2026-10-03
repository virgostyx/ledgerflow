# Partial lettering: settles a payment against invoices without requiring the group to balance. Debit and credit
# lines are matched oldest due date first; each match is recorded as an Accounting::LineAllocation. When every line
# linked by allocations is fully settled, the group is closed into a regular total Lettering. All or nothing.
class Accounting::AllocateLines
  extend LightService::Organizer

  def self.call(lines:)
    result = nil
    ApplicationRecord.transaction do
      # locked first: two people settling the same line at the same moment cannot both succeed
      locked = Accounting::JournalEntryLine.where(id: Array(lines).map(&:id)).order(:id).lock.includes(:journal_entry, :account, :invoice).to_a
      result = with(lines: locked).reduce(
        Accounting::Actions::ValidateAllocation,
        Accounting::Actions::CreateAllocations,
        Accounting::Actions::CloseSettledGroup
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    LightService::Context.make(lines: lines).tap { |ctx| ctx.fail!("Error: #{e.message}") }
  end
end
