# R16 fixed-asset movements table (docs/dev/reports/spec.md §13), per category (asset account family
# 21–24): A. acquisition value, B. depreciation, C. net book value = A − B, plus the gain or loss of the
# year's disposals and the I10 checks against the ledger. Read-only: it books nothing.
# Aggregation is in SQL over the register; nothing is summed from journal lines in Ruby.
class Accounting::FixedAssetMovementsQuery
  LABELS = { "21" => "Intangible fixed assets", "22" => "Land and buildings", "23" => "Plant, machinery and equipment",
             "24" => "Furniture and vehicles" }.freeze
  PREFIX = "LEFT(accounting_accounts.code, 2)".freeze
  COLUMNS = %i[cost_begin acquisitions disposals cost_end dep_begin dep_booked dep_reversed dep_end net_value].freeze

  Category = Struct.new(:code, :label, *COLUMNS, keyword_init: true)
  Disposal = Struct.new(:asset, :disposed_on, :cost, :accumulated, :net_book_value, :price, :gain_loss, keyword_init: true)
  Check    = Struct.new(:label, :register, :ledger, :difference, keyword_init: true)
  Result   = Struct.new(:fiscal_year, :categories, :totals, :disposals, :checks, keyword_init: true)

  def initialize(fiscal_year:)
    @fiscal_year = fiscal_year
    @start = fiscal_year.start_date
    @end   = fiscal_year.end_date
  end

  def call
    figures = figures_by_category
    categories = figures.keys.sort.map do |code|
      f = figures[code]
      Category.new(code: code, label: LABELS.fetch(code, code), **f, cost_end: f[:cost_begin] + f[:acquisitions] - f[:disposals],
                   dep_end: f[:dep_begin] + f[:dep_booked] - f[:dep_reversed]).tap { |c| c.net_value = c.cost_end - c.dep_end }
    end
    totals = Category.new(code: nil, label: "Total", **COLUMNS.index_with { |col| categories.sum(BigDecimal("0")) { |c| c[col] } })
    Result.new(fiscal_year: @fiscal_year, categories: categories, totals: totals, disposals: disposals, checks: checks(categories))
  end

  private

  def assets = Accounting::FixedAsset.joins(:asset_account).where.not(acquisition_value: nil)

  def entries = Accounting::DepreciationEntry.joins(:fiscal_year, fixed_asset: :asset_account)

  def sums(scope, column) = scope.group(Arel.sql(PREFIX)).sum(column).transform_values { |v| BigDecimal(v.to_s) }

  def figures_by_category
    cost_begin = sums(assets.where("acquisition_date < :s AND (disposed_on IS NULL OR disposed_on >= :s)", s: @start), :acquisition_value)
    acquisitions = sums(assets.where(acquisition_date: @start..@end), :acquisition_value)
    disposals = sums(assets.where(disposed_on: @start..@end), :acquisition_value)
    dep_begin = sums(entries.where("accounting_fiscal_years.start_date < :s AND (accounting_fixed_assets.disposed_on IS NULL OR accounting_fixed_assets.disposed_on >= :s)", s: @start), "accounting_depreciation_entries.amount")
    dep_booked = sums(entries.where(fiscal_year_id: @fiscal_year.id), "accounting_depreciation_entries.amount")
    dep_reversed = sums(entries.where(accounting_fixed_assets: { disposed_on: @start..@end }).where("accounting_fiscal_years.start_date <= ?", @start), "accounting_depreciation_entries.amount")

    codes = [ cost_begin, acquisitions, disposals, dep_begin, dep_booked, dep_reversed ].flat_map(&:keys).uniq
    codes.index_with do |code|
      { cost_begin: cost_begin[code], acquisitions: acquisitions[code], disposals: disposals[code], dep_begin: dep_begin[code],
        dep_booked: dep_booked[code], dep_reversed: dep_reversed[code] }.transform_values { |v| v || BigDecimal("0") }
    end
  end

  def disposals
    disposed = Accounting::FixedAsset.where(disposed_on: @start..@end).order(:disposed_on).to_a
    accumulated = Accounting::DepreciationEntry.where(fixed_asset_id: disposed.map(&:id)).group(:fixed_asset_id).sum(:amount)
    disposed.map do |asset|
      acc = BigDecimal(accumulated.fetch(asset.id, 0).to_s)
      nbv = (asset.acquisition_value || 0) - acc
      Disposal.new(asset: asset, disposed_on: asset.disposed_on, cost: asset.acquisition_value, accumulated: acc,
                   net_book_value: nbv, price: asset.disposal_price, gain_loss: asset.disposal_price && asset.disposal_price - nbv)
    end
  end

  # I10: register vs ledger balances of the fiscal year.
  def checks(categories)
    not_cost = Accounting::FixedAsset::NON_DEPRECIABLE_ACCOUNTS + Accounting::FixedAsset::DEPRECIATION_ACCOUNTS.values.map(&:last)
    cost_ledger = ledger_by_account_prefix("accounting_accounts.code ~ '^2[1-4]' AND accounting_accounts.code NOT IN (?)", not_cost)
    checks = categories.filter_map do |c|
      next unless Accounting::FixedAsset::DEPRECIATION_ACCOUNTS.key?(c.code)

      accumulated_code = Accounting::FixedAsset::DEPRECIATION_ACCOUNTS.fetch(c.code).last
      [ check("Acquisition value #{c.code} vs accounts #{c.code}x", c.cost_end, cost_ledger.select { |code, _| code.start_with?(c.code) }.values.sum(BigDecimal("0"))),
        check("Accumulated depreciation #{c.code} vs account #{accumulated_code}", c.dep_end, -ledger_balance("accounting_accounts.code = ?", accumulated_code)) ]
    end.flatten
    checks << check("Depreciation of the year vs accounts 630", categories.sum(BigDecimal("0"), &:dep_booked), income_ledger_balance("accounting_accounts.code LIKE '630%'"))
  end

  def check(label, register, ledger) = Check.new(label: label, register: register, ledger: ledger, difference: ledger - register)

  def ledger_lines
    Accounting::PostedLine.joins(:account).where(fiscal_year_id: @fiscal_year.id, entry_date: ..@end)
  end

  # Net debit balance of the accounts matching the SQL condition.
  def ledger_balance(condition, *args)
    BigDecimal(ledger_lines.where(condition, *args).sum("posted_lines.debit - posted_lines.credit").to_s)
  end

  # The balance of an income account of the year as the year's operations made it: the closing entry that settles it (F10), and the reversal of one that was taken back,
  # are not operations, and the year, once closed, must still agree with its register.
  def income_ledger_balance(condition, *args)
    operations = Accounting::JournalEntry.where(Accounting::TrialBalanceQuery::NOT_CLOSING, Accounting::JournalEntry::CLOSING_SOURCE, Accounting::JournalEntry::CLOSING_SOURCE).select(:id)
    BigDecimal(ledger_lines.where(journal_entry_id: operations).where(condition, *args).sum("posted_lines.debit - posted_lines.credit").to_s)
  end

  def ledger_by_account_prefix(condition, *args)
    ledger_lines.where(condition, *args).group("accounting_accounts.code").sum("posted_lines.debit - posted_lines.credit")
                .transform_values { |v| BigDecimal(v.to_s) }
  end
end
