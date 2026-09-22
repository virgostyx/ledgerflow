# Open lines on a partner account whose sign is reversed (an unallocated payment, a credit note) and that have
# stayed unused for at least `min_age_days`. One row per line, oldest first.
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
    l = "accounting_journal_entry_lines"
    net  = @kind == :customer ? "#{l}.debit - #{l}.credit" : "#{l}.credit - #{l}.debit"
    used = "COALESCE((SELECT SUM(al.amount) FROM accounting_line_allocations al " \
           "WHERE al.debit_line_id = #{l}.id OR al.credit_line_id = #{l}.id), 0)"
    amount = "(#{net}) - SIGN(#{net}) * #{used}"

    Accounting::JournalEntryLine
      .joins("JOIN accounting_journal_entries e ON e.id = #{l}.journal_entry_id")
      .joins("JOIN accounting_accounts a ON a.id = #{l}.account_id")
      .joins("LEFT JOIN accounting_partners p ON p.id = #{l}.partner_id")
      .where(lettering_id: nil)
      .where("e.status = ? AND e.entry_date <= ?", Accounting::JournalEntry.statuses[:posted], @as_of)
      .where("a.code LIKE ? AND a.reconcilable", Accounting::AgedBalanceQuery::PREFIX.fetch(@kind))
      .pluck(Arel.sql("p.name"), Arel.sql("e.reference"), Arel.sql("e.entry_date"), Arel.sql("(#{amount})"))
  end
end
