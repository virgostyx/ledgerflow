# Σ debit ≠ Σ credit on an entry (the database trigger should prevent it; this catches what slipped past).
class Accounting::Consistency::Checks::C01UnbalancedEntry < Accounting::Consistency::Check
  self.check_id = "C01"
  self.severity = "blocking"
  self.title = "Unbalanced entry"

  def call
    lines = Accounting::JournalEntryLine.all
    lines = lines.where(journal_entry_id: Accounting::JournalEntry.where(fiscal_year_id: @fiscal_year.id).select(:id)) if @fiscal_year
    lines.group(:journal_entry_id).having("SUM(debit) <> SUM(credit)")
                                .pluck(:journal_entry_id, Arel.sql("SUM(debit)"), Arel.sql("SUM(credit)")).map do |id, debit, credit|
      finding(subject: [ "Accounting::JournalEntry", id ], message: "Entry ##{id}: debit #{debit} ≠ credit #{credit}", debit: debit, credit: credit)
    end
  end
end
