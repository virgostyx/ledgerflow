# R03 — vue centralisatrice (docs/dev/reports/spec.md §6): par journal et par
# mois, nombre d'écritures et totaux débit/crédit. La vue détaillée de R03
# (écritures d'un journal, filtrables, dépliables) existe déjà via
# Accounting::JournalEntriesController#index — pas reconstruite ici.
class Accounting::JournalSummaryQuery
  Result = Struct.new(:journal_id, :journal_code, :month, :entry_count, :total_debit, :total_credit, keyword_init: true)

  def initialize(fiscal_year:)
    @fiscal_year = fiscal_year
  end

  def call
    rows = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(accounting_journal_entries: { fiscal_year_id: @fiscal_year.id,
                                            status: Accounting::JournalEntry.statuses[:posted] })
      .group("accounting_journal_entries.journal_id", "date_trunc('month', accounting_journal_entries.entry_date)")
      .select(
        "accounting_journal_entries.journal_id AS journal_id",
        "date_trunc('month', accounting_journal_entries.entry_date) AS month",
        "COUNT(DISTINCT accounting_journal_entries.id) AS entry_count",
        "SUM(accounting_journal_entry_lines.debit) AS total_debit",
        "SUM(accounting_journal_entry_lines.credit) AS total_credit"
      )

    journals = Accounting::Journal.where(id: rows.map(&:journal_id)).index_by(&:id)

    rows.map do |row|
      Result.new(
        journal_id:   row.journal_id,
        journal_code: journals[row.journal_id]&.code,
        month:        row.month.to_date,
        entry_count:  row.entry_count,
        total_debit:  BigDecimal(row.total_debit.to_s),
        total_credit: BigDecimal(row.total_credit.to_s)
      )
    end.sort_by { |r| [ r.journal_code.to_s, r.month ] }
  end
end
