# B02c: makes a snapshot of the books for the client's dashboard (nightly, and at each publication). The figures come from the existing queries (the trial balance, the aged balance), by SQL, for a
# whitelist of indicators; nothing names a third party; nothing is written in the books. The company may ask to approve a snapshot before the client sees it.
class PortalAdmin::GenerateSnapshot
  MONTHS = 12

  def self.call(entity:, today: Date.current)
    context = LightService::Context.make(snapshot: nil)
    return context.tap { |c| c.fail!("The client dashboard is not on for this company.") } unless entity.feature?(:b02a) && entity.feature?(:b02c)

    ActsAsTenant.with_tenant(entity) { context[:snapshot] = new(entity, today).make }
    context
  end

  def initialize(entity, today)
    @entity = entity
    @today = today
    @years = Accounting::FiscalYear.order(:start_date).to_a
  end

  def make
    indicators = whitelisted(compute_indicators, Portal::Snapshot::INDICATORS)
    series = whitelisted({ "sales" => month_series { |month| sales_between(month.beginning_of_month, month.end_of_month) }, "cash" => month_series { |month| cash_at(month.end_of_month) } }, Portal::Snapshot::SERIES)
    status = @entity.snapshot_approval_required? ? "pending_review" : "published"
    Portal::Snapshot.create!(entity_id: @entity.id, period_start: @today.beginning_of_month, period_end: @today, indicators: indicators, series: series, provisional: provisional?, generated_at: Time.current,
                             known_at: Time.current, sha256: Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate({ "indicators" => indicators, "series" => series })), status: status,
                             published_at: (Time.current if status == "published"))
  end

  private

  # Nothing leaves that is not on the list.
  def whitelisted(hash, list) = hash.slice(*list)

  def compute_indicators
    month = @today.beginning_of_month
    overdue = aged(:customer, @today)
    {
      "cash" => money(cash_at(@today)),
      "sales_month" => money(sales_between(month, @today)),
      "sales_previous_month" => money(sales_between(month << 1, (month << 1).end_of_month)),
      "sales_last_year" => money(sales_between(month << 12, (month << 12).end_of_month)),
      "result_ytd" => money(result_ytd),
      "receivables_overdue" => money(overdue.sum(&:overdue)),
      "receivables_overdue_count" => overdue.count { |row| row.overdue.positive? },
      "payables_30_days" => money(aged(:supplier, @today + 30).sum(&:overdue))
    }
  end

  def aged(kind, as_of) = Accounting::AgedBalanceQuery.new(kind: kind, as_of: as_of).call

  # The last 12 months, oldest first: [{ "month" => "2026-05", "value" => "1000.00" }].
  def month_series
    (0...MONTHS).map { |back| (@today.beginning_of_month << (MONTHS - 1 - back)) }.map { |month| { "month" => month.strftime("%Y-%m"), "value" => money(yield(month)) } }
  end

  def year_of(date) = @years.find { |year| year.start_date <= date && date <= year.end_date }

  def trial_balance(year, from, to) = Accounting::TrialBalanceQuery.new(fiscal_year: year, as_of: to, date_from: from, exclude_closing: true).call

  # What the sales accounts (70) earned from `from` to `to`: credits less debits of the movements.
  def sales_between(from, to)
    year = year_of(to) or return BigDecimal("0")
    trial_balance(year, [ from, year.start_date ].max, to).select { |row| row.code.start_with?("70") }.sum(BigDecimal("0")) { |row| row.movement_credit - row.movement_debit }
  end

  # What the cash accounts (55 and 57) hold at the end of the day, in the books of the year.
  def cash_at(date)
    year = year_of(date) or return BigDecimal("0")
    trial_balance(year, year.start_date, date).select { |row| row.code.start_with?("55", "57") }.sum(BigDecimal("0")) { |row| row.total_debit - row.total_credit }
  end

  def result_ytd
    year = year_of(@today) or return BigDecimal("0")
    rows = trial_balance(year, year.start_date, @today)
    rows.select { |row| row.code.start_with?("7") }.sum(BigDecimal("0")) { |row| row.total_credit - row.total_debit } -
      rows.select { |row| row.code.start_with?("6") }.sum(BigDecimal("0")) { |row| row.total_debit - row.total_credit }
  end

  def provisional? = year_of(@today)&.closed? != true

  # Two decimals, as a string: an amount never goes through a Float.
  def money(amount)
    whole, fraction = BigDecimal(amount.to_s).round(2).to_s("F").split(".")
    "#{whole}.#{fraction.to_s.ljust(2, '0')}"
  end
end
