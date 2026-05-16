class Accounting::Actions::ComputeVatGrids
  extend LightService::Action

  expects :fiscal_year_id, :period_start, :period_end
  promises :grids

  executed do |ctx|
    ctx.grids = Accounting::VatGridQuery.call(
      fiscal_year_id: ctx.fiscal_year_id,
      period_start:   ctx.period_start,
      period_end:     ctx.period_end
    ).transform_values { |v| format("%.2f", v) }
  end
end
