class Accounting::Settings::Actions::ValidateBankAccountParams
  extend LightService::Action

  expects :params

  executed do |ctx|
    p = ctx.params

    unless p[:label_fr].present?
      ctx.fail!("Label is required")
      next ctx
    end

    unless p[:journal_code].present? && p[:journal_code].length <= 8
      ctx.fail!("Journal code is required and must be 8 characters or less")
      next ctx
    end

    unless p[:iban].present? && IBANTools::IBAN.valid?(p[:iban])
      ctx.fail!("IBAN is invalid")
      next ctx
    end

    account = Accounting::Account.find_by(id: p[:default_account_id])
    unless account&.code&.start_with?("55")
      ctx.fail!("Counterpart account must be a 55xxxx bank account")
      next ctx
    end

    ctx[:counterpart_account] = account
  end
end
