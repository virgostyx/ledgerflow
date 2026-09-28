# Open (unlettered, at `as_of`) receivables or payables per partner, aged by due date.
# Due date, residual and "still open" reconstruction come from Accounting::OpenLineSql
# (docs/dev/reports/spec.md §7), shared with StaleCreditsQuery and UnletteredLinesQuery
# so their totals can never disagree (critère d'acceptation #4). Negative open amounts
# (unallocated payments, credit notes) go in `unallocated` and reduce the total.
class Accounting::AgedBalanceQuery
  BUCKETS = %i[not_due days_1_30 days_31_60 days_61_90 over_90].freeze
  PREFIX  = Accounting::OpenLineSql::PREFIX
  Row = Struct.new(:partner_name, *BUCKETS, :unallocated, :total, keyword_init: true) do
    # "Dont échu" / "% échu" (docs/dev/reports/spec.md §7): every bucket but not_due.
    def overdue = (BUCKETS - [ :not_due ]).sum { |b| public_send(b) }

    def overdue_pct
      return nil if total.zero?

      (overdue / total * 100).round(1)
    end
  end

  def self.totals(rows)
    Row.new(**Row.members.index_with { |m| m == :partner_name ? nil : rows.sum(BigDecimal("0")) { |r| r[m] } })
  end

  def initialize(kind:, as_of: Date.current)
    @kind  = kind.to_sym
    @as_of = as_of
  end

  def call
    open_lines.reject { |(_, amount, _)| amount.zero? }.group_by(&:first).map do |name, lines|
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
    Accounting::OpenLineSql.open_scope(kind: @kind, as_of: @as_of)
      .pluck(
        Arel.sql("p.name"),
        Arel.sql("(#{Accounting::OpenLineSql.residual(kind: @kind, as_of: @as_of)})"),
        Arel.sql(Accounting::OpenLineSql.due_date)
      )
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
