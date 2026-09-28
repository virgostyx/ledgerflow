# R17 closing regularizations report (docs/dev/reports/spec.md §13): the year's accruals with the amount at the
# cut-off (fiscal year end) and the state of their entries, the I11 checks against accounts 490/492, and the two
# cut-off help lists. Totals come from SQL over posted lines; nothing is booked here.
class Accounting::AccrualsReportQuery
  Row    = Struct.new(:accrual, :amount, :status, :missing_reversal, keyword_init: true)
  Check  = Struct.new(:label, :register, :ledger, :difference, keyword_init: true)
  Item   = Struct.new(:invoice, :reason, keyword_init: true)
  Result = Struct.new(:rows, :checks, :recorded_after_closing, :spanning_next_year, keyword_init: true)

  BOOKABLE_STATUSES = %w[posted paid partially_paid].freeze
  WINDOW_DAYS = 30

  def initialize(fiscal_year:)
    @fiscal_year = fiscal_year
    @cut_off = fiscal_year.end_date
  end

  def call
    accruals = Accounting::Accrual.where(fiscal_year_id: @fiscal_year.id)
                                  .includes(:journal_entry, :accrual_account, :pl_account, :reversal_entry).order(:accrual_type, :period_start).to_a
    rows = accruals.map { |a| Row.new(accrual: a, amount: a.amount_at(@cut_off), status: status_of(a), missing_reversal: a.booked? && a.reversal_entry_id.nil?) }
    Result.new(rows: rows, checks: checks(rows), recorded_after_closing: recorded_after_closing, spanning_next_year: spanning_next_year)
  end

  private

  def status_of(accrual)
    return :pending unless accrual.booked?

    accrual.journal_entry.posted? ? :posted : :draft
  end

  # I11: per type, Σ validated regularizations = the balance of the type's account at the cut-off.
  def checks(rows)
    Accounting::Accrual::ACCOUNT_CODES.map do |type, code|
      register = rows.select { |r| r.status == :posted && r.accrual.accrual_type.to_sym == type }.sum(BigDecimal("0"), &:amount)
      debit_nature = %i[deferred_charge accrued_income].include?(type)
      ledger = ledger_balance(code) * (debit_nature ? 1 : -1)
      Check.new(label: "#{type.to_s.humanize} vs account #{code}", register: register, ledger: ledger, difference: ledger - register)
    end
  end

  def ledger_balance(code)
    BigDecimal(Accounting::PostedLine.joins(:account).where(fiscal_year_id: @fiscal_year.id, entry_date: ..@cut_off, accounting_accounts: { code: code })
                                     .sum("posted_lines.debit - posted_lines.credit").to_s)
  end

  # Documents dated up to the closing but recorded in the following 30 days, or dated after it for a service ended before it.
  def recorded_after_closing
    window = (@cut_off + 1)..(@cut_off + WINDOW_DAYS)
    late_recorded = invoices.where(invoice_date: ..@cut_off).where("accounting_invoices.created_at::date BETWEEN ? AND ?", window.begin, window.end)
    service_before = invoices.where(invoice_date: window)
                             .where(id: Accounting::InvoiceLine.where("service_end <= ?", @cut_off).select(:invoice_id))
    (late_recorded.to_a.map { |i| Item.new(invoice: i, reason: "Dated up to the closing, recorded after it") } +
     service_before.to_a.reject { |i| late_recorded.exists?(i.id) }.map { |i| Item.new(invoice: i, reason: "Service ended before the closing") })
      .sort_by { |item| item.invoice.invoice_date }
  end

  # Invoices of the year with a line whose service period ends after the closing.
  def spanning_next_year
    invoices.where(invoice_date: @fiscal_year.start_date..@cut_off)
            .where(id: Accounting::InvoiceLine.where("service_end > ?", @cut_off).select(:invoice_id)).order(:invoice_date).map do |i|
      Item.new(invoice: i, reason: "Service runs into the next fiscal year")
    end
  end

  def invoices = Accounting::Invoice.where(status: BOOKABLE_STATUSES).includes(:partner)
end
