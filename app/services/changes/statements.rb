# B03b R21 "Impact sur les états": for the headings of the annual accounts (R07, R08), the cash, the VAT grids (R09) and the overdue receivables and payables (R04), the value at
# T1, at T2 and the variation. Every column is the very report computed with `known_at` at T1, then at T2: nothing is recomputed here. Only what moved is listed.
class Changes::Statements
  Row = Struct.new(:section, :code, :label, :at_t1, :at_t2, :variation, keyword_init: true)

  CASH_PREFIXES = %w[55 56 57].freeze # banks, postal accounts, cash

  def self.call(**args) = new(**args).call

  def initialize(fiscal_year:, from:, to: nil, as_of: nil)
    @fiscal_year = fiscal_year
    @as_of = as_of || fiscal_year.end_date
    @t1 = from
    @t2 = to || Time.current
  end

  def call = (annual_accounts + cash + vat + aged).reject { |row| row.variation.zero? }

  private

  def pair(section, code, label, before, after) = Row.new(section: section, code: code, label: label, at_t1: before, at_t2: after, variation: after - before)

  def annual_accounts
    before = Accounting::AnnualAccounts.new(fiscal_year: @fiscal_year, as_of: @as_of, known_at: @t1).call
    after = Accounting::AnnualAccounts.new(fiscal_year: @fiscal_year, as_of: @as_of, known_at: @t2).call
    Accounting::AnnualAccounts::STATEMENTS.flat_map do |statement|
      before.rows(statement).zip(after.rows(statement)).map { |b, a| pair(statement, a.code, a.label, b.amount, a.amount) }
    end
  end

  def cash
    totals = [ @t1, @t2 ].map do |time|
      Accounting::TrialBalanceQuery.new(fiscal_year: @fiscal_year, as_of: @as_of, known_at: time).call.select { |r| r.code.start_with?(*CASH_PREFIXES) }.sum(BigDecimal("0"), &:closing_net)
    end
    [ pair(:cash, "55/57", I18n.t("changes.statements.cash"), *totals) ]
  end

  def vat
    grids = [ @t1, @t2 ].map { |time| Accounting::VatGridQuery.call(fiscal_year_id: @fiscal_year.id, period_start: @fiscal_year.start_date, period_end: @as_of, known_at: time) }
    (grids.first.keys | grids.last.keys).sort.map { |grid| pair(:vat, grid, "Grid #{grid}", grids.first.fetch(grid, BigDecimal("0")), grids.last.fetch(grid, BigDecimal("0"))) }
  end

  # What is overdue, by the date of today: the aged balance is a reading of the open lines, not of a closing.
  def aged
    day = [ @as_of, Date.current ].min
    %i[customer supplier].map do |kind|
      totals = [ @t1, @t2 ].map { |time| Accounting::AgedBalanceQuery.totals(Accounting::AgedBalanceQuery.new(kind: kind, as_of: day, known_at: time).call).overdue }
      pair(:aged, kind.to_s, I18n.t("changes.statements.overdue_#{kind}"), *totals)
    end
  end
end
