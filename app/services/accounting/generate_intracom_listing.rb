class Accounting::GenerateIntracomListing
  extend LightService::Organizer

  def self.call(fiscal_year_id:, period_start:, period_end:)
    result = nil
    ApplicationRecord.transaction do
      result = with(
        fiscal_year_id: fiscal_year_id,
        period_start:   period_start,
        period_end:     period_end
      ).reduce(
        Accounting::Actions::ComputeIntracomListingLines,
        Accounting::Actions::CreateIntracomListing
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    ctx = LightService::Context.make(fiscal_year_id: fiscal_year_id)
    ctx.fail!("Error: #{e.message}")
    ctx
  end
end
