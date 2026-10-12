# A person registers the bank account of a supplier (B01b). It starts unverified and is observed (`iban_cooling_hours` of the entity, 24 by default); it is not
# usable in a payment batch until another person verifies it and the observation is over. A change - a new account for a supplier that has a verified one - is
# told to the owners; the account in use stays the one in use until the new one is verified. Nothing here is reached by a document: only a person calls it.
# => ctx[:account]; on a refusal ctx[:code] (:feature_off, :not_allowed, :invalid)
class Payments::RegisterBankAccount
  def self.call(partner:, iban:, holder_name:, user:, bic: nil, source: :manual)
    ctx = LightService::Context.make(account: nil)
    entity = partner.entity
    return refuse(ctx, :feature_off) unless entity.feature?(:b01b)
    return refuse(ctx, :not_allowed) unless Accounting::PartnerBankAccountPolicy.new(user, nil).register?

    ApplicationRecord.transaction do
      current = Accounting::PartnerBankAccount.where(partner: partner, status: :verified).order(:verified_at).last
      now = Time.current
      account = Accounting::PartnerBankAccount.create!(partner: partner, iban: iban, bic: bic.presence, holder_name: holder_name, source: source, created_by: user,
                                                       previous_account: current, first_seen_at: now, cooling_until: now + entity.iban_cooling_hours.hours)
      Accounting::AuditLog.record!(auditable: account, action: "bank_account_registered", user: user,
                                   payload: { partner_id: partner.id, iban: account.masked_iban, source: source.to_s, cooling_until: account.cooling_until.iso8601 })
      announce_change(account, current, user) if current
      ctx[:account] = account
    end
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx[:code] = :invalid
    ctx.fail!(e.record.errors.full_messages.to_sentence)
    ctx
  end

  # The owners are told that a supplier's account changed, and which one it replaces: it is the moment a fraud would show.
  def self.announce_change(account, replaced, user)
    Accounting::AuditLog.record!(auditable: account, action: "bank_account_changed", user: user, payload: { partner_id: account.partner_id, iban: account.masked_iban, replaces: replaced.id })
    UserEntity.owners.current.where(entity_id: account.entity_id).includes(:user).each do |membership|
      Accounting::Notify.call(user: membership.user, event: "bank_account_changed:#{account.id}", subject: account, data: { by: user.full_name, message: account.partner.name })
    end
  end
  private_class_method :announce_change

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.bank_accounts.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end
