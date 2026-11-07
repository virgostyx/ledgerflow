class Payments::Actions::ValidateBatchBankAccount
  extend LightService::Action

  expects :bank_account

  executed do |ctx|
    ctx.fail!(I18n.t("payments.errors.no_iban_account", label: ctx.bank_account.label_fr)) and next if ctx.bank_account.no_iban?
    next if ctx.bank_account.currency == "EUR"

    ctx.fail!(I18n.t("payments.errors.foreign_account", label: ctx.bank_account.label_fr))
  end
end
