class Accounting::Actions::ValidateBalance
  extend LightService::Action

  expects :entry

  executed do |ctx|
    debit  = ctx.entry.lines.sum(:debit)
    credit = ctx.entry.lines.sum(:credit)

    unless (debit - credit).abs <= BigDecimal("0.01")
      ctx.fail_with_rollback!(
        I18n.t("accounting.errors.unbalanced_entry", debit: debit, credit: credit)
      )
    end
  end
end
