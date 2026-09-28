# R12 pivot (docs/dev/reports/spec.md §12): class 6/7 accounts as rows, columns = the
# analytical accounts of `axis` (each line weighted by its annotation percentage) or months.
# "Non ventilé" = row total − allocated part, so every row adds up to the ledger figure and the
# report total equals R08's result (invariant I8). Revenue is credit − debit, expense debit − credit.
class Accounting::AnalyticPivotQuery
  UNASSIGNED = :unassigned

  Row    = Struct.new(:account, :kind, :cells, :total, keyword_init: true)
  Result = Struct.new(:rows, :columns, :net_result, keyword_init: true)

  SIGNED = <<~SQL.squish.freeze
    CASE WHEN accounting_accounts.account_type = #{Accounting::Account.account_types[:revenue]}
         THEN posted_lines.credit - posted_lines.debit
         ELSE posted_lines.debit - posted_lines.credit END
  SQL

  def initialize(fiscal_year:, axis: nil, period: nil, columns: :analytic)
    @fiscal_year = fiscal_year
    @axis        = axis
    @period      = period || (fiscal_year.start_date..fiscal_year.end_date)
    @columns     = columns
  end

  def call
    totals = scope.group("posted_lines.account_id").sum(SIGNED)
    cells  = @columns == :month ? month_cells : analytic_cells(totals)
    accounts = Accounting::Account.where(id: totals.keys).order(:code).index_by(&:id)

    rows = accounts.map do |id, account|
      row_cells = cells.fetch(id, {}).transform_values { |v| BigDecimal(v.to_s) }
      Row.new(account: account, kind: account.revenue? ? :revenue : :expense, cells: row_cells, total: BigDecimal(totals[id].to_s))
    end
    net = rows.sum(BigDecimal("0")) { |r| r.kind == :revenue ? r.total : -r.total }
    Result.new(rows: rows, columns: column_keys(rows), net_result: net)
  end

  private

  def scope
    Accounting::PostedLine.joins(:account)
      .where(fiscal_year_id: @fiscal_year.id, entry_date: @period,
             accounting_accounts: { account_type: [ Accounting::Account.account_types[:expense], Accounting::Account.account_types[:revenue] ] })
  end

  def month_cells
    scope.group("posted_lines.account_id", "to_char(posted_lines.entry_date, 'YYYY-MM')").sum(SIGNED)
         .each_with_object(Hash.new { |h, k| h[k] = {} }) { |((account_id, month), v), h| h[account_id][month] = v }
  end

  def analytic_cells(totals)
    allocated = scope.joins(<<~SQL.squish)
      INNER JOIN accounting_analytical_annotations ann
        ON ann.journal_entry_line_id = posted_lines.id AND ann.analytical_axis_id = #{Integer(@axis.id)}
    SQL
      .group("posted_lines.account_id", "ann.analytical_account_id")
      .sum("(#{SIGNED}) * ann.percentage / 100")

    cells = Hash.new { |h, k| h[k] = {} }
    allocated.each { |(account_id, analytic_id), v| cells[account_id][analytic_id] = v }
    totals.each do |account_id, total|
      cells[account_id][UNASSIGNED] = BigDecimal(total.to_s) - cells[account_id].values.sum(BigDecimal("0")) { |v| BigDecimal(v.to_s) }
    end
    cells
  end

  def column_keys(rows)
    keys = rows.flat_map { |r| r.cells.keys }.uniq
    return keys.sort if @columns == :month

    ids = Accounting::AnalyticalAccount.where(id: keys - [ UNASSIGNED ]).order(:code).pluck(:id)
    ids + [ UNASSIGNED ]
  end
end
