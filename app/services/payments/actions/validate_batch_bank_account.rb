class Payments::Actions::ValidateBatchBankAccount
  extend LightService::Action

  expects :bank_account

  executed do |ctx|
    next if ctx.bank_account.currency == "EUR"

    ctx.fail!(I18n.t("payments.errors.foreign_account", label: ctx.bank_account.label_fr))
  end
end
