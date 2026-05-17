class Accounting::Settings::Actions::PersistBankAccount
  extend LightService::Action

  expects :params, :journal

  executed do |ctx|
    p = ctx.params
    bank_account = Accounting::BankAccount.new(
      journal:  ctx.journal,
      label_fr: p[:label_fr],
      label_nl: p[:label_nl],
      iban:     p[:iban]&.upcase&.gsub(/\s+/, ""),
      bic:      p[:bic]&.upcase,
      currency: p[:currency].presence || "EUR",
      notes:    p[:notes],
      active:   true
    )

    if bank_account.save
      ctx[:bank_account] = bank_account
    else
      ctx.fail!(bank_account.errors.full_messages.first)
    end
  end
end
