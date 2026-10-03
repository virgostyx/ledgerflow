# The two accounts that take the rounding differences of bank payments (F02): 658100 (a charge) and 758100 (an income). New
# entities get them with their chart; on an existing one the owner creates them, knowingly: nothing is added to a chart behind
# anyone's back. Idempotent. Audited when it creates something.
class Accounting::CreateRoundingAccounts
  ACCOUNTS = [
    { code: Accounting::AccountCodes::ROUNDING_LOSS, label_fr: "Écarts d'arrondi (charge)", account_class: 6, account_type: :expense, normal_balance: :debit },
    { code: Accounting::AccountCodes::ROUNDING_GAIN, label_fr: "Écarts d'arrondi (produit)", account_class: 7, account_type: :revenue, normal_balance: :credit }
  ].freeze

  def self.call(user:)
    ctx = LightService::Context.make(created: [])
    return ctx.tap { |c| c.fail!(I18n.t("errors.not_authorized")) } unless Accounting::Settings::BasePolicy.new(user, :settings).destroy?

    ApplicationRecord.transaction do
      ACCOUNTS.each do |attrs|
        next if Accounting::Account.exists?(code: attrs[:code])

        Accounting::Account.create!(**attrs, is_leaf: true, reconcilable: false)
        ctx[:created] << attrs[:code]
      end
      Accounting::AuditLog.record!(auditable: ActsAsTenant.current_tenant, action: "rounding_accounts_created", user: user, payload: { codes: ctx[:created] }) if ctx[:created].any?
    end
    ctx
  end

  # Both accounts exist in the current entity: the tolerance can be used.
  def self.ready? = Accounting::Account.where(code: ACCOUNTS.map { |a| a[:code] }).count == ACCOUNTS.size
end
