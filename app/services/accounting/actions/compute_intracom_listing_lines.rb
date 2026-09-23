class Accounting::Actions::ComputeIntracomListingLines
  extend LightService::Action

  expects :fiscal_year_id, :period_start, :period_end
  promises :listing_lines

  executed do |ctx|
    ctx.listing_lines = Accounting::IntracomListingQuery.call(
      fiscal_year_id: ctx.fiscal_year_id,
      period_start:   ctx.period_start,
      period_end:     ctx.period_end
    )
  end
end
