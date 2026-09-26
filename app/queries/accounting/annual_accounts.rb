# The annual accounts of a fiscal year in the abridged Belgian model for companies: balance sheet (assets, liabilities)
# and income statement, by legal heading, next to the previous fiscal year when there is one. The headings and the
# accounts they group are in config/annual_accounts/company_abridged.yml.
#
# Balances come from Accounting::TrialBalanceQuery without the closing entry, so a closed year reads like an open one. The
# result of the year (heading 9904) is added to the profit carried forward (14) and the result account is left out.
class Accounting::AnnualAccounts
  MODEL = Rails.root.join("config/annual_accounts/company_abridged.yml")
  STATEMENTS = %i[assets liabilities income].freeze
  IGNORED_PREFIXES = %w[0 69 79].freeze # off-balance accounts; appropriations of the result, including the result account

  Row = Struct.new(:code, :label, :level, :amount, :previous, keyword_init: true)
  Unmapped = Struct.new(:code, :label, :balance, keyword_init: true)

  Report = Struct.new(:fiscal_year, :previous_year, :rows_by_statement, :difference, :unmapped, keyword_init: true) do
    def rows(statement) = rows_by_statement.fetch(statement)
    def balanced? = difference.zero?
  end

  def initialize(fiscal_year:)
    @fiscal_year = fiscal_year
  end

  def call
    previous_year = Accounting::FiscalYear.where("end_date < ?", @fiscal_year.start_date).order(end_date: :desc).first
    balances = balances_of(@fiscal_year)
    figures = figures_for(balances)
    previous = previous_year && figures_for(balances_of(previous_year))

    rows = STATEMENTS.index_with do |statement|
      definition.fetch(statement.to_s).map do |row|
        Row.new(code: row["code"], label: row["label"], level: row["level"], amount: figures.fetch(row["code"]), previous: previous&.fetch(row["code"]))
      end
    end
    Report.new(fiscal_year: @fiscal_year, previous_year: previous_year, rows_by_statement: rows,
               difference: figures.fetch("20/58") - figures.fetch("10/49"), unmapped: unmapped(balances))
  end

  private

  def definition = @definition ||= YAML.safe_load_file(MODEL)

  def balances_of(fiscal_year)
    Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, exclude_closing: true).call
  end

  # { heading code => amount }; the income statement first: the balance sheet uses its result.
  def figures_for(balances)
    figures = {}
    %w[income assets liabilities].each do |statement|
      definition.fetch(statement).each { |row| figures[row["code"]] = amount_of(row, balances, figures) }
    end
    figures
  end

  def amount_of(row, balances, figures)
    if row["sum"]
      row["sum"].sum(BigDecimal("0")) { |part| part.start_with?("-") ? -figures.fetch(part.delete_prefix("-")) : figures.fetch(part) }
    else
      own = balances.select { |b| covers?(row, b.code) }.sum(BigDecimal("0")) { |b| row["side"] == "debit" ? b.total_debit - b.total_credit : b.total_credit - b.total_debit }
      (own + Array(row["add"]).sum(BigDecimal("0")) { |code| figures.fetch(code) }).round(2)
    end
  end

  def covers?(row, code) = row["prefixes"].any? { |prefix| code.start_with?(prefix) } && Array(row["except"]).exclude?(code)

  def unmapped(balances)
    leaves = definition.values.flatten.select { |row| row["prefixes"] }
    balances.reject { |b| b.total_debit == b.total_credit || IGNORED_PREFIXES.any? { |p| b.code.start_with?(p) } || leaves.any? { |row| covers?(row, b.code) } }
            .map { |b| Unmapped.new(code: b.code, label: b.label_fr, balance: b.total_debit - b.total_credit) }
  end
end
