class Accounting::Actions::ValidateInvoice
  extend LightService::Action

  expects :invoice

  executed do |ctx|
    invoice = ctx.invoice

    unless invoice.draft?
      ctx.fail_with_rollback!(I18n.t("accounting.invoices.errors.already_posted"))
      next
    end

    if invoice.lines.empty?
      ctx.fail_with_rollback!(I18n.t("accounting.invoices.errors.no_lines"))
      next
    end

    # A filed VAT return is frozen: a late invoice belongs in a regularization, not in that period.
    # ponytail: only invoice posting is guarded; manual journal entries are not (documented in R09.md).
    if Accounting::VatDeclaration.where(status: %i[submitted accepted])
         .exists?([ "period_start <= :d AND period_end >= :d", { d: invoice.invoice_date } ])
      ctx.fail_with_rollback!(I18n.t("accounting.invoices.errors.vat_period_filed"))
    end
  end
end
