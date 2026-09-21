# Open (unlettered) receivables or payables per partner, aged by due date at `as_of`.
# Due date is the invoice's, or the entry date for lines without an invoice.
# Negative open amounts (unallocated payments, credit notes) go in `unallocated` and reduce the total.
class Accounting::AgedBalanceQuery
  BUCKETS = %i[not_due days_1_30 days_31_60 days_61_90 over_90].freeze
  Row = Struct.new(:partner_name, *BUCKETS, :unallocated, :total, keyword_init: true)

  PREFIX = { customer: "40%", supplier: "44%" }.freeze

  def self.totals(rows)
    Row.new(**Row.members.index_with { |m| m == :partner_name ? nil : rows.sum(BigDecimal("0")) { |r| r[m] } })
  end

  def initialize(kind:, as_of: Date.current)
    @kind  = kind.to_sym
    @as_of = as_of
  end

  def call
    open_lines.group_by(&:first).map do |name, lines|
      row = Row.new(partner_name: name, **Row.members.excluding(:partner_name).index_with { BigDecimal("0") })
      lines.each do |(_, amount, due_date)|
        slot = amount.negative? ? :unallocated : bucket(@as_of - due_date)
        row[slot] += amount
        row.total  += amount
      end
      row
    end.sort_by { |r| [ r.partner_name.nil? ? 1 : 0, r.partner_name.to_s ] }
  end

  private

  # => [[partner_name, amount, due_date], ...]
  def open_lines
    l = "accounting_journal_entry_lines"
    amount = @kind == :customer ? "#{l}.debit - #{l}.credit" : "#{l}.credit - #{l}.debit"

    Accounting::JournalEntryLine
      .joins("JOIN accounting_journal_entries e ON e.id = #{l}.journal_entry_id")
      .joins("JOIN accounting_accounts a ON a.id = #{l}.account_id")
      .joins("LEFT JOIN accounting_partners p ON p.id = #{l}.partner_id")
      .joins("LEFT JOIN accounting_invoices i ON i.id = #{l}.invoice_id")
      .where(lettering_id: nil)
      .where("e.status = ? AND e.entry_date <= ?", Accounting::JournalEntry.statuses[:posted], @as_of)
      .where("a.code LIKE ? AND a.reconcilable", PREFIX.fetch(@kind))
      .pluck(Arel.sql("p.name"), Arel.sql("(#{amount})"), Arel.sql("COALESCE(i.due_date, e.entry_date)"))
  end

  def bucket(days_overdue)
    case days_overdue
    when ..0    then :not_due
    when 1..30  then :days_1_30
    when 31..60 then :days_31_60
    when 61..90 then :days_61_90
    else             :over_90
    end
  end
end
