# Step 7 of the closing (F10): the accruals and deferrals (R17). Each regularization of the year is booked, its entry validated, its reversal drafted for the
# next year, and the register agrees with the accounts 490 to 493 (I11). The step books and drafts the reversals that are missing; a person validates
# the entries, which the closing never does for them.
class Closing::Steps::Accruals < Closing::Step
  self.position = 7
  self.code     = "accruals"
  self.title    = "Accruals and deferrals"
  self.kind     = :action
  self.blocking = true

  def evaluate
    report = Accounting::AccrualsReportQuery.new(fiscal_year: fiscal_year).call
    gaps = report.checks.reject { |c| c.difference.zero? }
    details = { "unbooked" => report.rows.count { |r| r.status == :pending }, "drafts" => report.rows.count { |r| r.status == :draft },
                "missing_reversals" => report.rows.count(&:missing_reversal),
                "i11_gaps" => gaps.map { |c| { "label" => c.label, "difference" => money(c.difference) } } }
    return pending(details) if details.values_at("unbooked", "drafts", "missing_reversals").any?(&:positive?)

    gaps.any? ? blocked(details) : ok(details)
  end

  def perform(user:)
    ctx = LightService::Context.make(booked: 0, reversed: 0)
    Accounting::Accrual.where(fiscal_year: fiscal_year).includes(:journal_entry).find_each do |accrual|
      unless accrual.booked?
        booked = Accounting::BookAccrual.call(accrual: accrual)
        next ctx.fail!("#{accrual.description}: #{booked.message}") if booked.failure?

        accrual.reload.journal_entry.update_columns(closing_run_id: run.id) # validated in the batch of the closing; its reversal waits for the next year
        ctx[:booked] += 1
      end
      next if accrual.reload.reversal_entry_id

      reversed = Accounting::ReverseAccrual.call(accrual: accrual)
      next ctx.fail!("#{accrual.description}: #{reversed.message}") if reversed.failure?

      ctx[:reversed] += 1
    end
    Accounting::AuditLog.record!(auditable: run, action: "closing_accruals_booked", user: user, payload: { booked: ctx[:booked], reversed: ctx[:reversed] }) if ctx.success?
    ctx
  end
end
