# An invoice received from a third party arrives with lines it could not code (suspense account): the accountant
# must code them before it is posted. Invoices typed in the UI are not concerned.
class Accounting::Actions::ValidateInvoiceCoding
  extend LightService::Action

  expects :invoice

  executed do |ctx|
    next unless ctx.invoice.external_digest.present?

    suspense = Accounting::AccountCodes::TRANSIT
    if ctx.invoice.lines.joins(:account).exists?(accounting_accounts: { code: suspense })
      ctx.fail_with_rollback!(I18n.t("accounting.invoices.errors.uncoded_lines", code: suspense))
    end
  end
end
