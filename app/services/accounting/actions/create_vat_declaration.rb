class Accounting::Actions::CreateVatDeclaration
  extend LightService::Action

  expects :fiscal_year_id, :period_start, :period_end, :period_type, :grids
  promises :vat_declaration

  executed do |ctx|
    decl = Accounting::VatDeclaration.create!(
      fiscal_year_id: ctx.fiscal_year_id,
      period_start:   ctx.period_start,
      period_end:     ctx.period_end,
      period_type:    ctx.period_type,
      grids:          ctx.grids
    )
    ctx.vat_declaration = decl
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!(e.record.errors.full_messages.join(", "))
  end
end
