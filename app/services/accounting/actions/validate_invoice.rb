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
    end
  end
end
