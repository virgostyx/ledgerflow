# R03 (docs/dev/reports/spec.md §6): detects gaps in a journal's reference
# sequence for a fiscal year ("PREFIXYYYY/NNNN", see Journal#next_sequence_number).
class Accounting::JournalNumberingGaps
  def initialize(journal:, fiscal_year:)
    @journal     = journal
    @fiscal_year = fiscal_year
  end

  def call
    numbers = Accounting::JournalEntry
      .where(journal: @journal, fiscal_year: @fiscal_year, status: Accounting::JournalEntry.ledger_status_values)
      .where("reference LIKE ?", "#{@journal.sequence_prefix}#{@fiscal_year.year}/%")
      .pluck(:reference)
      .map { |ref| ref.split("/").last.to_i }
      .sort

    return [] if numbers.size < 2

    (numbers.first..numbers.last).to_a - numbers
  end
end
