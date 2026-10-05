# F12a: the health snapshot of ONE entity, worked out from its own books with the services that already exist (closing F10, VAT R09, checks R19, bank F02,
# Peppol F06, inbox F03, tasks F08, aged balance R04), and written as the row of the day. It must be called in the tenant of the entity: no query here goes
# across entities, which is what lets the dashboard show a portfolio without ever reading several books at once.
class Portfolio::Snapshot
  VAT_DUE_DAY = 20 # a return is due on the 20th of the month after its period (the rule of the Belgian VAT code for monthly and quarterly filers)
  OPEN_TASKS = %w[open in_progress blocked].freeze

  # => the DossierHealthSnapshot of `on` (updated when the day already has one)
  def self.call(entity, on: Date.current) = new(entity, on).call

  def initialize(entity, on)
    @entity = entity
    @on = on
  end

  def call
    row = DossierHealthSnapshot.find_or_initialize_by(entity_id: @entity.id, taken_on: @on)
    row.assign_attributes(computed_at: Time.current, **closing, **vat, **checks, **bank, **peppol, inbox_documents: Accounting::Document.inbox.count,
                          overdue_tasks: Accounting::Task.where(status: OPEN_TASKS).where("due_on < ?", @on).count, overdue_receivables: overdue_receivables, last_posted_on: last_posted_on)
    row.save!
    row
  end

  private

  def closing
    year = Accounting::FiscalYear.where.not(status: :closed).order(:start_date).first
    return { closing_status: "closed", closing_progress: 100, closing_year: Accounting::FiscalYear.order(:start_date).last&.year } unless year

    run = Accounting::ClosingRun.active.where(fiscal_year_id: year.id).order(:id).last
    status = run ? (run.ready? ? "ready" : "in_progress") : "open"
    { closing_status: status, closing_progress: run&.progress, closing_year: year.year }
  end

  def vat
    return { next_vat_due_on: nil, vat_overdue: false } if @entity.franchise?

    due = first_unfiled_period_due
    { next_vat_due_on: due, vat_overdue: due.present? && due < @on }
  end

  # The due date of the first period of the open year that has no submitted or accepted return.
  def first_unfiled_period_due
    year = Accounting::FiscalYear.where.not(status: :closed).order(:start_date).first or return
    filed = Accounting::VatDeclaration.where(fiscal_year_id: year.id, status: %i[submitted accepted]).pluck(:period_start).to_set
    step = @entity.vat_filing_frequency == "monthly" ? 1 : 3
    from = year.start_date
    while from <= year.end_date
      to = [ (from >> step) - 1, year.end_date ].min
      return (to + 1.month).change(day: VAT_DUE_DAY) unless filed.include?(from)

      from >>= step
    end
    nil
  end

  def checks
    run = Accounting::ConsistencyRun.where.not(finished_at: nil).latest_first.first
    return { blocking_count: nil, warning_count: nil, consistency_run_at: nil } unless run

    { blocking_count: run.counts["blocking"].to_i, warning_count: run.counts["warning"].to_i, consistency_run_at: run.finished_at }
  end

  def bank
    waiting = Accounting::BankTransaction.where(status: :pending)
    oldest = waiting.minimum(:transaction_date)
    { unreconciled_bank_lines: waiting.count, oldest_unreconciled_days: oldest && (@on - oldest).to_i }
  end

  def peppol
    inbound = Accounting::PeppolMessage.where(direction: :inbound)
    { peppol_pending: inbound.where(status: :received).count,
      peppol_anomalies: Accounting::PeppolMessage.where(status: %i[needs_review failed]).count }
  end

  def overdue_receivables
    rows = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: @on).call
    Accounting::AgedBalanceQuery.totals(rows).overdue
  end

  def last_posted_on
    Accounting::JournalEntry.in_ledger.pick(Arel.sql("MAX(COALESCE(locked_at, updated_at))"))&.to_date
  end
end
