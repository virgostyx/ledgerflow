# R14 cash forecast (docs/dev/reports/spec.md §12): weekly columns from today's ledger cash
# (accounts 55/57) plus open receivables/payables at their due dates (same reconstruction as R04,
# Accounting::OpenLineSql), the estimated VAT payment and the manual/recurring items.
#
# Scenarios — base: items at their due date, overdue ones in week 1; prudent: receipts slip by
# the client's observed average delay + `prudent_days`; optimistic: receipts come `early_days`
# earlier (payables and manual items never move).
class Accounting::CashForecastQuery
  HORIZONS  = { weeks_13: 13, months_6: 26 }.freeze
  SCENARIOS = %i[base prudent optimistic].freeze
  VAT_DUE_DAY = 20 # legal due day of the month following the period (Belgium)

  Week   = Struct.new(:index, :from, :to, :opening, :inflows, :outflows, :closing, :alert, :sources, keyword_init: true)
  Result = Struct.new(:weeks, :scenario, :threshold, keyword_init: true)

  def initialize(start: Date.current, horizon: :weeks_13, scenario: :base, prudent_days: 10, early_days: 5, threshold: 0)
    @start        = start
    @weeks_count  = HORIZONS.fetch(horizon.to_sym)
    @scenario     = SCENARIOS.include?(scenario.to_sym) ? scenario.to_sym : :base
    @prudent_days = prudent_days.to_i
    @early_days   = early_days.to_i
    @threshold    = BigDecimal(threshold.to_s)
    @last_day     = start + @weeks_count * 7 - 1
  end

  def call
    movements = Hash.new { |h, k| h[k] = { in: BigDecimal("0"), out: BigDecimal("0"), sources: Hash.new(BigDecimal("0")) } }
    receivable_items.each { |date, amount| add(movements, date, :in, amount, :receivables) }
    payable_items.each    { |date, amount, source| add(movements, date, :out, amount, source) }
    vat_item&.then        { |date, amount| add(movements, date, :out, amount, :vat) }
    manual_items.each     { |date, dir, amount| add(movements, date, dir, amount, :manual) }
    recurring_items.each  { |date, dir, amount| add(movements, date, dir, amount, :recurring) }

    balance = opening_cash
    weeks = (1..@weeks_count).map do |n|
      from = @start + (n - 1) * 7
      m = movements[n]
      closing = balance + m[:in] - m[:out]
      week = Week.new(index: n, from: from, to: from + 6, opening: balance, inflows: m[:in], outflows: m[:out],
                      closing: closing, alert: closing < @threshold, sources: m[:sources].dup)
      balance = closing
      week
    end
    Result.new(weeks: weeks, scenario: @scenario, threshold: @threshold)
  end

  private

  # Week number of a date (overdue = week 1); nil past the horizon. Negative amounts (credit notes,
  # unallocated payments) are not tied to a due date and follow the same rule.
  def week_of(date)
    return 1 if date < @start
    return nil if date > @last_day

    (date - @start).to_i / 7 + 1
  end

  def add(movements, date, direction, amount, source)
    week = week_of(date) or return
    slot = movements[week]
    slot[direction] += amount
    slot[:sources][source] += amount
  end

  def opening_cash
    Accounting::PostedLine.joins(:account)
      .where("accounting_accounts.code LIKE '55%' OR accounting_accounts.code LIKE '57%'")
      .where(entry_date: ..@start).sum("posted_lines.debit - posted_lines.credit")
  end

  # [[date, amount], ...] — customer residuals shifted per scenario.
  def receivable_items
    lateness = @scenario == :prudent ? average_lateness_by_partner : {}
    open_items(:customer).map do |partner_id, amount, due, _|
      shift = case @scenario
      when :prudent then (lateness[partner_id] || 0) + @prudent_days
      when :optimistic then -@early_days
      else 0
      end
      [ due + shift, amount ]
    end
  end

  # [[date, amount, source], ...]: what is owed to suppliers, by where it stands for payment (B01a). Everything is an outflow;
  # the source says whether it is approved (or needs no approval, or is not an invoice), still waits for approval, or is held.
  def payable_items = open_items(:supplier).map { |_, amount, due, payment_status| [ due, amount, payable_source(payment_status) ] }

  PENDING_STATUSES = [ Accounting::Invoice.payment_statuses[:to_approve] ].freeze
  HELD_STATUSES = Accounting::Invoice.payment_statuses.values_at(:on_hold, :disputed).freeze

  def payable_source(payment_status)
    return :payables_pending if PENDING_STATUSES.include?(payment_status)
    return :payables_held if HELD_STATUSES.include?(payment_status)

    :payables
  end

  def open_items(kind)
    Accounting::OpenLineSql.open_scope(kind: kind, as_of: @start)
      .pluck(Arel.sql("accounting_journal_entry_lines.partner_id"),
             Arel.sql("(#{Accounting::OpenLineSql.residual(kind: kind, as_of: @start)})"),
             Arel.sql(Accounting::OpenLineSql.due_date), Arel.sql("i.payment_status"))
      .reject { |_, amount, _, _| amount.zero? }
      .map { |partner_id, amount, due, payment_status| [ partner_id, BigDecimal(amount.to_s), due, payment_status ] }
  end

  # Payment delay observed per client on settled invoices: amount-weighted days between due date and
  # allocation, never negative (an early payer is not assumed to pay early).
  def average_lateness_by_partner
    Accounting::LineAllocation
      .joins("JOIN accounting_journal_entry_lines dl ON dl.id = accounting_line_allocations.debit_line_id")
      .joins("JOIN accounting_accounts da ON da.id = dl.account_id")
      .joins("JOIN accounting_invoices di ON di.id = dl.invoice_id")
      .where("da.code LIKE '40%' AND di.due_date IS NOT NULL AND accounting_line_allocations.allocated_on <= ?", @start)
      .group("dl.partner_id")
      .pluck(Arel.sql("dl.partner_id"),
             Arel.sql("SUM(accounting_line_allocations.amount * (accounting_line_allocations.allocated_on - di.due_date)) / SUM(accounting_line_allocations.amount)"))
      .to_h { |partner_id, days| [ partner_id, [ days.to_f.round, 0 ].max ] }
  end

  # Net VAT owed by the ledger to date (450100 credit − 410100 debit), paid at the next legal due day.
  def vat_item
    payable = Accounting::PostedLine.joins(:account).where(accounting_accounts: { code: Accounting::AccountCodes::VAT_PAYABLE }, entry_date: ..@start)
                                    .sum("posted_lines.credit - posted_lines.debit")
    deductible = Accounting::PostedLine.joins(:account).where(accounting_accounts: { code: Accounting::AccountCodes::VAT_DEDUCTIBLE }, entry_date: ..@start)
                                       .sum("posted_lines.debit - posted_lines.credit")
    owed = payable - deductible
    return nil unless owed.positive? # a refund is never counted on (prudent)

    due = Date.new(@start.year, @start.month, VAT_DUE_DAY)
    due = due.next_month if due < @start
    [ due, owed ]
  end

  # Recurring entries that ask to feed the forecast (F07): their due dates within the horizon, read from the schedule.
  def recurring_items
    Accounting::RecurringEntry.where(feeds_cash_forecast: true, status: %i[active blocked]).includes(entry_template: { lines: :account }).flat_map do |recurring|
      direction = recurring.forecast_direction
      next [] unless direction

      recurring.upcoming_dates(60).select { |date| date.between?(@start, @last_day) }.filter_map do |date|
        amount = recurring.forecast_amount(date)
        [ date, direction, amount ] if amount
      end
    end
  end

  def manual_items
    Accounting::CashForecastItem.active.flat_map do |item|
      item.occurrences_between(@start, @last_day).map { |date| [ date, item.inflow? ? :in : :out, item.amount ] }
    end
  end
end
