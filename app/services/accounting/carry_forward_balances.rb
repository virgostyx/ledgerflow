class Accounting::CarryForwardBalances
  extend LightService::Organizer

  def self.call(new_fiscal_year:, closed_by:)
    result = nil
    ApplicationRecord.transaction do
      result = with(
        new_fiscal_year: new_fiscal_year,
        closed_by:       closed_by
      ).reduce(
        Accounting::Actions::FindClosedFiscalYear,
        Accounting::Actions::ComputeCarryForwardBalances,
        Accounting::Actions::CreateOpeningBalanceEntry
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    ctx = LightService::Context.make(new_fiscal_year: new_fiscal_year)
    ctx.fail!("Error: #{e.message}")
    ctx
  end
end
