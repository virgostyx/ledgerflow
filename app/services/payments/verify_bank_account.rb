# Another person verifies the bank account of a supplier, after calling them on a number known before the request - never the number on the invoice or in the
# message that announced the change (B01b). Who registered it cannot verify it. The account then replaces the supplier's earlier ones (superseded, kept with their
# history); it is usable once its observation is over.
# => ctx[:account]; on a refusal ctx[:code] (:not_allowed, :method_required, :not_unverified, :same_person)
class Payments::VerifyBankAccount
  def self.call(account:, user:, method:, note: nil)
    ctx = LightService::Context.make(account: account)
    return refuse(ctx, :not_allowed) unless Accounting::PartnerBankAccountPolicy.new(user, account).verify?
    return refuse(ctx, :method_required) unless Accounting::PartnerBankAccount.verification_methods.key?(method.to_s)
    return refuse(ctx, :not_unverified) unless account.unverified?
    return refuse(ctx, :same_person) if account.created_by_id == user.id

    ApplicationRecord.transaction do
      account.update!(status: :verified, verified_by: user, verified_at: Time.current, verification_method: method, verification_note: note.presence)
      Accounting::AuditLog.record!(auditable: account, action: "bank_account_verified", user: user, payload: { partner_id: account.partner_id, iban: account.masked_iban, method: method.to_s })
      replace_earlier(account, user)
    end
    ctx
  end

  def self.replace_earlier(account, user)
    Accounting::PartnerBankAccount.where(partner_id: account.partner_id, status: %i[verified unverified]).where.not(id: account.id).find_each do |earlier|
      earlier.update!(status: :superseded)
      Accounting::AuditLog.record!(auditable: earlier, action: "bank_account_superseded", user: user, payload: { partner_id: earlier.partner_id, iban: earlier.masked_iban, replaced_by: account.id })
    end
  end
  private_class_method :replace_earlier

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.bank_accounts.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end
