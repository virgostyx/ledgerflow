# Writes a journal entry as a draft, the way the entry screen does (F01): the lines and the entry in one transaction, the double-entry check deferred to the end of it, the author on the entry. The one
# door to a new manual draft, for the screen and for whatever a person accepts on behalf of the agent (A07). It validates nothing more than the model does; the screen's callers check rights and periods.
# `source` ([type, id]) says where a generated draft comes from, so that the audit trail can tell.
# => Result with the entry and whether it was saved (the entry carries its errors when it was not).
class Accounting::CreateDraftEntry
  Result = Struct.new(:entry, :saved) do
    alias_method :saved?, :saved
  end

  def self.call(attributes:, user:, source: nil)
    entry = Accounting::JournalEntry.new(attributes.merge(created_by: user))
    entry.source_type, entry.source_id = source if source
    saved = ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      entry.save
    end
    Result.new(entry, saved)
  end
end
