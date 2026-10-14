# Open (unlettered, at `as_of`) receivables or payables per partner, aged by due date.
# Due date, residual and "still open" reconstruction come from Accounting::OpenLineSql
# (docs/dev/reports/spec.md §7), shared with StaleCreditsQuery and UnletteredLinesQuery
# so their totals can never disagree (critère d'acceptation #4). Negative open amounts
# (unallocated payments, credit notes) go in `unallocated` and reduce the total.
class Accounting::AgedBalanceQuery
  include Accounting::HistoricalCaching

  BUCKETS = %i[not_due days_1_30 days_31_60 days_61_90 over_90].freeze
  PREFIX  = Accounting::OpenLineSql::PREFIX
  Row = Struct.new(:partner_id, :partner_name, *BUCKETS, :unallocated, :total, keyword_init: true) do
    # "Dont échu" / "% échu" (docs/dev/reports/spec.md §7): every bucket but not_due.
    def overdue = (BUCKETS - [ :not_due ]).sum { |b| public_send(b) }

    def overdue_pct
      return nil if total.zero?

      (overdue / total * 100).round(1)
    end
  end

  def self.totals(rows)
    Row.new(**Row.members.index_with { |m| %i[partner_id partner_name].include?(m) ? nil : rows.sum(BigDecimal("0")) { |r| r[m] } })
  end

  # known_at (B03a): the balance as it was known at that instant (a Time or an Accounting::KnownAt); refused before the start of the history.
  def initialize(kind:, as_of: Date.current, known_at: nil)
    @kind  = kind.to_sym
    @as_of = as_of
    @known_at = Accounting::KnownAt.wrap(known_at).ensure_viewable!
  end

  def call
    cached do
      open_lines.reject { |(_, _, amount, _)| amount.zero? }.group_by(&:second).map do |name, lines|
        row = Row.new(partner_id: lines.first.first, partner_name: name, **Row.members.excluding(:partner_id, :partner_name).index_with { BigDecimal("0") })
        lines.each do |(_, _, amount, due_date)|
          slot = amount.negative? ? :unallocated : bucket(@as_of - due_date)
          row[slot] += amount
          row.total  += amount
        end
        row
      end.sort_by { |r| [ r.partner_name.nil? ? 1 : 0, r.partner_name.to_s ] }
    end
  end

  private

  def cache_parts = { kind: @kind, as_of: @as_of }

  # => [[partner_id, partner_name, amount, due_date], ...]
  def open_lines
    Accounting::OpenLineSql.open_scope(kind: @kind, as_of: @as_of, known_at: @known_at)
      .pluck(
        Arel.sql("p.id"),
        Arel.sql(Accounting::MasterData.partner_name_sql(@known_at)),
        Arel.sql("(#{Accounting::OpenLineSql.residual(kind: @kind, as_of: @as_of, known_at: @known_at)})"),
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
