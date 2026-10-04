# Step 12 of the closing (F10): the revaluation of the foreign currencies. Ok when there is nothing to book (no foreign balance, or the entity's treatment books
# none of the differences), or when the draft entry Fx::Revalue made is posted; blocked while a closing rate is missing; pending while the entry is to be
# generated or to be validated by a person.
class Closing::Steps::Revaluation < Closing::Step
  self.position = 12
  self.code     = "revaluation"
  self.title    = "Foreign currency revaluation"
  self.kind     = :action
  self.blocking = true

  def evaluate
    existing = Fx::Revalue.existing(fiscal_year: fiscal_year)
    return existing.posted? ? ok("entry_id" => existing.id) : pending("draft_entry_id" => existing.id) if existing

    plan = Fx::Revalue.plan(fiscal_year: fiscal_year)
    return blocked("missing_rates" => plan.missing) if plan.missing.any?

    plan.amounts.empty? ? ok("amounts" => []) : pending("amounts" => plan.amounts.map { |currency, kind, amount| { "currency" => currency, "kind" => kind.to_s, "amount" => money(amount) } })
  end

  def perform(user:)
    plan = Fx::Revalue.plan(fiscal_year: fiscal_year)
    return LightService::Context.make(entry: nil) if plan.missing.empty? && plan.amounts.empty? && Fx::Revalue.existing(fiscal_year: fiscal_year).nil? # nothing to book

    result = Fx::Revalue.call(fiscal_year: fiscal_year)
    result[:entry]&.update_columns(closing_run_id: run.id) if result.success? # validated in the batch of the closing, with the other entries it drafted
    Accounting::AuditLog.record!(auditable: run, action: "closing_revaluation_drafted", user: user, payload: { entry_id: result[:entry]&.id }) if result.success?
    result
  end
end
