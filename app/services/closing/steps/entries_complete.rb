# Step 2 of the closing (F10): the books are complete. No entry in draft in the year (the drafts the closing itself makes belong to its steps 15 and 16),
# and no task of the type "closing" left open (F08): those warn, and go on once acknowledged with a comment.
class Closing::Steps::EntriesComplete < Closing::Step
  self.position = 2
  self.code     = "entries_complete"
  self.title    = "Complete entry"
  self.kind     = :check
  self.blocking = true

  def evaluate
    drafts = Accounting::JournalEntry.for_fiscal_year(fiscal_year).where(status: :draft).where("closing_run_id IS NULL OR closing_run_id <> ?", run.id).count
    tasks  = Accounting::Task.open_ones.where(kind: :closing).count
    details = { "drafts" => drafts, "tasks" => tasks }
    return blocked(details) if drafts.positive?

    tasks.positive? ? warning(details) : ok(details)
  end
end
