# Open lines on a partner account whose sign is reversed (an unallocated payment, a credit note) and that have
# stayed unused for at least `min_age_days`. One row per line, oldest first.
# Reconstruction shared with AgedBalanceQuery via Accounting::OpenLineSql (docs/dev/reports/spec.md §7).
class Accounting::StaleCreditsQuery
  Row = Struct.new(:partner_name, :reference, :entry_date, :amount, :age_days, keyword_init: true)

  def initialize(kind:, as_of: Date.current, min_age_days: 90)
    @kind         = kind.to_sym
    @as_of        = as_of
    @min_age_days = min_age_days
  end

  def call
    open_lines.filter_map do |name, reference, entry_date, amount|
      next if amount >= 0

      age = (@as_of - entry_date).to_i
      next if age < @min_age_days

      Row.new(partner_name: name, reference: reference, entry_date: entry_date, amount: -amount, age_days: age)
    end.sort_by { |r| -r.age_days }
  end

  private

  def open_lines
    Accounting::JournalEntryLine
      .joins("JOIN accounting_journal_entries e ON e.id = accounting_journal_entry_lines.journal_entry_id")
      .joins("JOIN accounting_accounts a ON a.id = accounting_journal_entry_lines.account_id")
      .joins("LEFT JOIN accounting_partners p ON p.id = accounting_journal_entry_lines.partner_id")
      .joins("LEFT JOIN accounting_invoices i ON i.id = accounting_journal_entry_lines.invoice_id")
      .joins("LEFT JOIN accounting_letterings lt ON lt.id = accounting_journal_entry_lines.lettering_id")
      .where("e.status IN (?) AND e.entry_date <= ?", Accounting::JournalEntry.ledger_status_values, @as_of)
      .where("a.code LIKE ? AND a.reconcilable", Accounting::OpenLineSql::PREFIX.fetch(@kind))
      .pluck(
        Arel.sql("p.name"), Arel.sql("e.reference"), Arel.sql("e.entry_date"),
        Arel.sql("(#{Accounting::OpenLineSql.residual(kind: @kind, as_of: @as_of)})")
      )
  end
end
