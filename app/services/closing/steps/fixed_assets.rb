# Step 6 of the closing (F10): the fixed assets. The depreciation of the year is booked and validated for every asset (the step books what is missing,
# once), and the register agrees with the ledger (I10, R16).
class Closing::Steps::FixedAssets < Closing::Step
  self.position = 6
  self.code     = "fixed_assets"
  self.title    = "Fixed assets"
  self.kind     = :action
  self.blocking = true

  def evaluate
    to_book = Accounting::PostDepreciation.pending(fiscal_year).size
    gaps = Accounting::FixedAssetMovementsQuery.new(fiscal_year: fiscal_year).call.checks.reject { |c| c.difference.zero? }
    details = { "to_book" => to_book, "i10_gaps" => gaps.map { |c| { "label" => c.label, "difference" => money(c.difference) } } }
    return pending(details) if to_book.positive?

    gaps.any? ? blocked(details) : ok(details)
  end

  def perform(user:)
    result = Accounting::PostDepreciation.call(fiscal_year: fiscal_year)
    Accounting::AuditLog.record!(auditable: run, action: "closing_depreciation_booked", user: user, payload: { entries: result[:entries].size }) if result.success?
    result
  end
end
