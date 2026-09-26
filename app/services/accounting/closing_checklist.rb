# What is left to do before a fiscal year is closed, computed on the fly. Each check is ok, a warning (the closing is
# allowed) or blocking (Accounting::CloseFiscalYear refuses); the wording and the link to fix it are the view's business.
# Blocking checks: entries in draft, depreciation to book, a balance sheet that does not balance.
class Accounting::ClosingChecklist
  Check  = Struct.new(:key, :status, :count, :amount, keyword_init: true)
  Result = Struct.new(:checks, keyword_init: true) do
    def blocking? = checks.any? { |c| c.status == :blocking }
    def warnings_count = checks.count { |c| c.status == :warning }
  end

  STALE_CREDIT_DAYS = 90

  def initialize(fiscal_year:, as_of: Date.current)
    @fiscal_year = fiscal_year
    @as_of       = as_of
    @entity      = fiscal_year.entity
  end

  def call
    checks = [ draft_entries, depreciation, balance, draft_invoices, bank, overdue_receivables, stale_credits ]
    checks += [ vat_declarations ] unless @entity.franchise?
    checks += [ vat_review ] if @entity.vat_scheme_mixed? && !@entity.franchise?
    checks << next_fiscal_year
    Result.new(checks: checks)
  end

  private

  def check(key, count, problem_status, amount: nil)
    Check.new(key: key, count: count, amount: amount, status: count.zero? ? :ok : problem_status)
  end

  def draft_entries
    check(:draft_entries, Accounting::JournalEntry.for_fiscal_year(@fiscal_year).where(status: :draft).count, :blocking)
  end

  def depreciation
    check(:depreciation, Accounting::PostDepreciation.pending(@fiscal_year).size, :blocking)
  end

  # The balance sheet model is the one of companies: accounts that fit no heading may explain a difference (an ASBL, an
  # unusual account), so that case only warns; a difference nothing explains blocks.
  def balance
    report = Accounting::AnnualAccounts.new(fiscal_year: @fiscal_year).call
    return Check.new(key: :balance, status: :ok, count: 0, amount: BigDecimal("0")) if report.balanced?

    report.unmapped.any? ? Check.new(key: :balance, status: :warning, count: report.unmapped.size, amount: report.difference) :
                           Check.new(key: :balance, status: :blocking, count: 1, amount: report.difference)
  end

  def draft_invoices
    check(:draft_invoices, Accounting::Invoice.where(fiscal_year: @fiscal_year, status: :draft).count, :warning)
  end

  def bank
    check(:bank, Accounting::BankTransaction.pending.where(transaction_date: @fiscal_year.start_date..@fiscal_year.end_date).count, :warning)
  end

  def overdue_receivables
    rows = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: @fiscal_year.end_date).call.select { |r| r.over_90.positive? }
    check(:overdue_receivables, rows.size, :warning, amount: rows.sum(BigDecimal("0"), &:over_90))
  end

  def stale_credits
    count = %i[customer supplier].sum do |kind|
      Accounting::StaleCreditsQuery.new(kind: kind, as_of: @fiscal_year.end_date, min_age_days: STALE_CREDIT_DAYS).call.size
    end
    check(:stale_credits, count, :warning)
  end

  # The periods already over (at `as_of`, within the year) whose VAT declaration was not submitted.
  def vat_declarations
    step  = @entity.vat_filing_frequency == "monthly" ? 1 : 3
    limit = [ @as_of, @fiscal_year.end_date ].min
    filed = Accounting::VatDeclaration.where(fiscal_year: @fiscal_year, status: %i[submitted accepted]).pluck(:period_start)

    due = 0
    start = @fiscal_year.start_date
    while (start >> step) - 1 <= limit && start <= @fiscal_year.end_date
      due += 1 unless filed.include?(start)
      start >>= step
    end
    check(:vat_declarations, due, :warning)
  end

  def vat_review
    check(:vat_review, Accounting::FixedAsset.all.count { |asset| asset.under_review?(@fiscal_year.year) }, :warning)
  end

  def next_fiscal_year
    exists = Accounting::FiscalYear.exists?(start_date: @fiscal_year.end_date + 1)
    Check.new(key: :next_fiscal_year, status: exists ? :ok : :info, count: exists ? 0 : 1)
  end
end
