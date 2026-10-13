# What a rejected or returned payment leaves behind (B01c §6 "Conséquences de sécurité"): the invoice is held, with the reason, so that nothing pays it again by itself to the same
# account; the account paid goes back to unverified for a new observation (an IBAN that comes back is very often wrong or fraudulent); the owners are warned and a task asks to contact
# the supplier. `outcome` is "rejected" or "returned".
module Payments::HoldAfterFailedPayment
  def self.call(item:, outcome:, reason:, user:)
    item.item_invoices.includes(:invoice).each { |link| hold(link.invoice, outcome, reason, user) }
    distrust(item, outcome, reason, user)
  end

  def self.hold(invoice, outcome, reason, user)
    invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[:on_hold])
    Payments::Hold.create!(invoice: invoice, reason: "Payment #{outcome}: #{reason}", created_by: user)
  end
  private_class_method :hold

  def self.distrust(item, outcome, reason, user)
    account = item.partner_bank_account or return
    account.update!(status: :unverified, verified_by: nil, verified_at: nil, verification_method: nil, verification_note: nil,
                    cooling_until: Time.current + account.entity.iban_cooling_hours.hours)
    Accounting::AuditLog.record!(auditable: account, action: "bank_account_distrusted", user: user, payload: { partner_id: account.partner_id, iban: account.masked_iban, reason: "payment #{outcome}", detail: reason })
    invoice = item.item_invoices.includes(:invoice).first&.invoice
    task = Accounting::Task.create!(title: "Contact the supplier #{item.partner.name}: a payment was #{outcome}", kind: :to_check, priority: :high, target: invoice || account,
                                    description: "Payment #{item.end_to_end_id} to #{account.masked_iban} was #{outcome}: #{reason}. The account is unverified again: call the supplier on a number known before, then verify a new account.")
    UserEntity.owners.current.where(entity_id: item.entity_id).includes(:user).each do |membership|
      Accounting::Notify.call(user: membership.user, event: "bank_account_distrusted:#{account.id}", subject: invoice || account, data: { message: item.partner.name, task_id: task.id })
    end
  end
  private_class_method :distrust
end
