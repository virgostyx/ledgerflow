# Assembles R01 (docs/dev/reports/spec.md §5) into a Reports::Result: runs
# Accounting::TrialBalanceQuery for the requested period, decorates each row
# with the comparative period's closing balance when asked, and totals
# Σ débit / Σ crédit / the period's result (Σ classe 7 − Σ classe 6).
class Accounting::TrialBalanceReport
  Row = Struct.new(:row, :comparative_closing, keyword_init: true) do
    def method_missing(name, *args, &block) = row.send(name, *args, &block)
    def respond_to_missing?(name, include_private = false) = row.respond_to?(name, include_private) || super

    def variation_amount = row.closing_net - comparative_closing

    def variation_pct
      return nil if comparative_closing.zero?

      (variation_amount / comparative_closing * 100).round(1)
    end
  end

  def initialize(filters:)
    @filters = filters
  end

  def call
    fiscal_year = Accounting::FiscalYear.find(@filters.fiscal_year_id)
    date_from   = @filters.date_from || fiscal_year.start_date
    as_of       = @filters.date_to   || fiscal_year.end_date

    rows = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, date_from: date_from, as_of: as_of).call
    rows = decorate_with_comparative(rows, fiscal_year, as_of) if @filters.comparative.present?

    Reports::Result.new(rows: rows, totals: totals(rows), filters: @filters, currency: "EUR")
  end

  private

  def decorate_with_comparative(rows, fiscal_year, as_of)
    comparative_fiscal_year = comparative_fiscal_year_for(fiscal_year)
    comparative_by_code =
      if comparative_fiscal_year
        Accounting::TrialBalanceQuery.new(fiscal_year: comparative_fiscal_year, as_of: as_of - 1.year)
          .call.index_by(&:code)
      else
        {}
      end

    rows.map { |row| Row.new(row: row, comparative_closing: comparative_by_code[row.code]&.closing_net || BigDecimal("0")) }
  end

  # Only :previous_year is implemented for R01 v1 — :previous (immediately preceding
  # period, same fiscal year) needs Reports::Period#comparative_period wired in when a
  # future report actually asks for it (see docs/dev/reports/QUESTIONS.md).
  def comparative_fiscal_year_for(fiscal_year)
    return unless @filters.comparative == "previous_year"

    Accounting::FiscalYear.find_by(year: fiscal_year.year - 1)
  end

  # Row wrappers forward unknown methods to the underlying TrialBalanceQuery::Result
  # (see Row#method_missing above), so total_debit/account_type/balance work either way.
  def totals(rows)
    result = rows.select { |r| r.account_type == "revenue" }.sum(&:balance) -
             rows.select { |r| r.account_type == "expense" }.sum(&:balance)

    { debit: rows.sum(&:total_debit), credit: rows.sum(&:total_credit), result: result }
  end
end
