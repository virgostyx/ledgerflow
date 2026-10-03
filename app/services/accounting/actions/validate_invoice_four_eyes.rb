# F01: the author of an invoice may not post it when the entity asks for a second person. Runs after the totals are known.
class Accounting::Actions::ValidateInvoiceFourEyes
  extend LightService::Action

  expects :invoice

  executed do |ctx|
    ctx.fail_with_rollback!(I18n.t("accounting.errors.four_eyes")) if ctx.invoice.four_eyes_blocks?(Current.user)
  end
end
