# R13 dashboard indicators (docs/dev/reports/spec.md §12). Every figure comes from a source
# service (TrialBalanceQuery for R01/R07/R08 balances, AgedBalanceQuery for R04); nothing is
# recomputed from entry lines. One failing indicator yields a card with `error`, never a crash.
class Accounting::DashboardKpis
  Card = Struct.new(:key, :label, :unit, :value, :formula, :source, :status, :error, keyword_init: true)

  def initialize(fiscal_year:, as_of: Date.current)
    @fiscal_year = fiscal_year
    @as_of       = [ as_of, fiscal_year.end_date ].min
  end

  def call
    [
      card(:cash, "Available cash", :money, "Σ balances of accounts 55 and 57", :trial_balance) { cash },
      card(:revenue_ytd, "Revenue year to date", :money, "Σ class 70 (credit − debit)", :income_statement) { revenue },
      card(:gross_margin_pct, "Gross margin", :percent, "(class 70 − class 60) ÷ class 70", :income_statement) { gross_margin_pct },
      card(:fixed_costs_monthly, "Monthly fixed costs", :money, "Average per elapsed month of the accounts marked fixed", :income_statement) { fixed_costs_monthly },
      card(:result_ytd, "Result year to date", :money, "Σ class 7 − Σ class 6", :income_statement) { result },
      card(:dso, "DSO (days)", :days, "Customer receivables (40) ÷ amounts invoiced (debits of 40) × days elapsed", :aged_balance) { dso },
      card(:dpo, "DPO (days)", :days, "Supplier payables (44) ÷ amounts purchased (credits of 44) × days elapsed", :aged_balance) { dpo },
      card(:working_capital, "Working capital requirement", :money, "(Stocks 3 + trade receivables 40 + other receivables 41) − trade payables 44", :balance_sheet) { working_capital },
      card(:overdue_receivables, "Overdue customer receivables", :money, "Total of the overdue buckets of the customer aged balance", :aged_balance) { overdue_receivables },
      card(:cash_coverage_months, "Cash coverage (months)", :months, "Available cash ÷ monthly fixed costs", :trial_balance) { cash_coverage }
    ]
  end

  private

  def card(key, label, unit, formula, source)
    value = yield
    Card.new(key: key, label: label, unit: unit, value: value, formula: formula, source: source, status: status_for(key, value))
  rescue StandardError => e
    Rails.logger.error("[DashboardKpis] #{key}: #{e.class}: #{e.message}")
    Card.new(key: key, label: label, unit: unit, formula: formula, source: source, error: "Could not compute this indicator.")
  end

  # ponytail: fixed default thresholds; per-entity configuration when asked.
  def status_for(key, value)
    return nil if value.nil?

    case key
    when :cash, :result_ytd then value.negative? ? :danger : :ok
    when :cash_coverage_months then value < 1 ? :danger : (value < 3 ? :warning : :ok)
    when :dso then value > 90 ? :danger : (value > 60 ? :warning : :ok)
    end
  end

  def balances
    @balances ||= Accounting::TrialBalanceQuery.new(fiscal_year: @fiscal_year, as_of: @as_of).call
  end

  def net(*prefixes, sign: :debit)
    rows = balances.select { |r| prefixes.any? { |p| r.code.start_with?(p) } }
    rows.sum(BigDecimal("0")) { |r| sign == :debit ? r.total_debit - r.total_credit : r.total_credit - r.total_debit }
  end

  def total(prefix, side) = balances.select { |r| r.code.start_with?(prefix) }.sum(BigDecimal("0")) { |r| r.public_send("total_#{side}") }

  def days_elapsed = (@as_of - @fiscal_year.start_date + 1).to_i

  def months_elapsed = (@as_of.year * 12 + @as_of.month) - (@fiscal_year.start_date.year * 12 + @fiscal_year.start_date.month) + 1

  def ratio(numerator, denominator, scale = 1)
    denominator.zero? ? nil : numerator / denominator * scale
  end

  def cash = net("55", "57")
  def revenue = net("70", sign: :credit)
  def gross_margin_pct = ratio(revenue - net("60"), revenue, 100)
  def result = net("7", sign: :credit) - net("6")

  def fixed_costs_monthly
    codes = Accounting::Account.where(fixed_cost: true).pluck(:code)
    return BigDecimal("0") if codes.empty?

    balances.select { |r| codes.include?(r.code) }.sum(BigDecimal("0")) { |r| r.total_debit - r.total_credit } / months_elapsed
  end

  def dso = ratio(net("40"), total("40", :debit), days_elapsed)
  def dpo = ratio(net("44", sign: :credit), total("44", :credit), days_elapsed)
  def working_capital = net("3") + net("40") + net("41") - net("44", sign: :credit)

  def overdue_receivables
    rows = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: @as_of).call
    Accounting::AgedBalanceQuery.totals(rows).overdue
  end

  def cash_coverage = ratio(cash, fixed_costs_monthly)
end
