# R20 filing data (docs/dev/reports/spec.md §13): the balance sheet and income statement figures per rubric
# code (R07, R08) and the year's VAT declaration grids (R09), as plain data. Generating the official XML
# filings from the official schemas is a separate phase, not covered here.
class Accounting::FilingData
  def self.call(fiscal_year:) = new(fiscal_year).call

  def initialize(fiscal_year)
    @fiscal_year = fiscal_year
  end

  def call
    report = Accounting::AnnualAccounts.new(fiscal_year: @fiscal_year).call
    {
      fiscal_year: { year: @fiscal_year.year, start_date: @fiscal_year.start_date.to_s, end_date: @fiscal_year.end_date.to_s },
      balance_sheet: { assets: rubrics(report.rows(:assets)), liabilities: rubrics(report.rows(:liabilities)) },
      income_statement: rubrics(report.rows(:income)),
      vat_declarations: vat_declarations
    }
  end

  private

  def rubrics(rows)
    rows.map { |r| { code: r.code, label: r.label, amount: money(r.amount), previous: r.previous && money(r.previous) } }
  end

  def vat_declarations
    Accounting::VatDeclaration.where(fiscal_year_id: @fiscal_year.id).order(:period_start).map do |d|
      { period_start: d.period_start.to_s, period_end: d.period_end.to_s, period_type: d.period_type, status: d.status,
        grids: d.grids.sort.to_h { |code, amount| [ code, money(BigDecimal(amount.to_s)) ] } }
    end
  end

  def money(value) = BigDecimal(value.to_s).to_s("F")
end
