# Takes a bank account out of use, with a reason (a payment returned, a supplier that warned of a fraud). A blocked account is never usable again: a new
# one is registered, observed and verified. (B01b)
# => ctx[:account]; on a refusal ctx[:code] (:not_allowed, :reason_required)
class Payments::BlockBankAccount
  def self.call(account:, user:, reason:)
    ctx = LightService::Context.make(account: account)
    return refuse(ctx, :not_allowed) unless Accounting::PartnerBankAccountPolicy.new(user, account).block?
    return refuse(ctx, :reason_required) if reason.blank?
    return refuse(ctx, :not_blockable) unless account.unverified? || account.verified?

    ApplicationRecord.transaction do
      account.update!(status: :blocked, blocked_reason: reason)
      Accounting::AuditLog.record!(auditable: account, action: "bank_account_blocked", user: user, payload: { partner_id: account.partner_id, iban: account.masked_iban, reason: reason })
    end
    ctx
  end

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.bank_accounts.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end
