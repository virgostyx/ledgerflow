# R12 margin per analytical account (docs/dev/reports/spec.md §12): revenue − direct costs, then
# the unallocated expenses ("Non ventilé") spread as a separate, labelled overhead share by a
# configurable key (:revenue or :direct_costs). Built on AnalyticPivotQuery so no figure is
# recomputed elsewhere. The last account absorbs the rounding cent, so shares add up to the overhead.
class Accounting::AnalyticMarginQuery
  Row = Struct.new(:analytical_account, :revenue, :direct_costs, :margin, :margin_pct, :overhead_share,
                   :margin_after_overhead, keyword_init: true)
  Result = Struct.new(:rows, :overhead, :undistributed, keyword_init: true)

  KEYS = %i[revenue direct_costs].freeze

  def initialize(fiscal_year:, axis:, period: nil, allocation_key: :revenue)
    raise ArgumentError, "allocation_key must be one of #{KEYS}" unless KEYS.include?(allocation_key)

    @pivot = Accounting::AnalyticPivotQuery.new(fiscal_year: fiscal_year, axis: axis, period: period)
    @key   = allocation_key
  end

  def call
    pivot    = @pivot.call
    accounts = Accounting::AnalyticalAccount.where(id: pivot.columns - [ Accounting::AnalyticPivotQuery::UNASSIGNED ]).order(:code)
    overhead = pivot.rows.select { |r| r.kind == :expense }.sum(BigDecimal("0")) { |r| r.cells.fetch(:unassigned, 0) }

    rows = accounts.map do |acct|
      revenue = sum_for(pivot, acct.id, :revenue)
      costs   = sum_for(pivot, acct.id, :expense)
      Row.new(analytical_account: acct, revenue: revenue, direct_costs: costs, margin: revenue - costs,
              margin_pct: revenue.zero? ? nil : ((revenue - costs) / revenue * 100).round(2))
    end
    distribute(rows, overhead)
    Result.new(rows: rows, overhead: overhead, undistributed: overhead - rows.sum(BigDecimal("0"), &:overhead_share))
  end

  private

  def sum_for(pivot, column, kind)
    pivot.rows.select { |r| r.kind == kind }.sum(BigDecimal("0")) { |r| r.cells.fetch(column, 0) }.round(2)
  end

  def distribute(rows, overhead)
    keys  = rows.map { |r| [ r.revenue, r.direct_costs ].then { |rev, dc| @key == :revenue ? rev : dc }.clamp(0, nil) }
    total = keys.sum
    given = BigDecimal("0")
    last  = keys.rindex(&:positive?)
    rows.each_with_index do |row, i|
      share = total.zero? ? BigDecimal("0") : (overhead * keys[i] / total).round(2)
      share = overhead - given if i == last # absorb the rounding remainder
      given += share
      row.overhead_share = share
      row.margin_after_overhead = row.margin - share
    end
  end
end
