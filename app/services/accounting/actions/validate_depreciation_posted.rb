# A fiscal year cannot be closed while a fixed asset still has depreciation to book for it.
class Accounting::Actions::ValidateDepreciationPosted
  extend LightService::Action

  expects :fiscal_year

  executed do |ctx|
    pending = Accounting::PostDepreciation.pending(ctx.fiscal_year)

    if pending.any?
      ctx.fail!(I18n.t("accounting.fiscal_years.errors.depreciation_pending", assets: pending.map { |asset, _| asset.description }.to_sentence))
    end
  end
end
