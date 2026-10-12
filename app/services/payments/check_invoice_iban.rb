# The IBAN written on a purchase invoice is compared with the verified account of the supplier (B01b). When it is another one, nothing is changed in the
# supplier's file - a document never changes a bank account - but the owners are told and a task is opened to call the supplier on a number known before.
# Told once per invoice (the task carries a fingerprint). Nothing to compare with when the supplier has no verified account.
class Payments::CheckInvoiceIban
  def self.call(invoice:)
    return unless invoice.supplier? && invoice.iban.present? && invoice.entity.feature?(:b01b)

    verified = Accounting::PartnerBankAccount.where(partner_id: invoice.partner_id, status: :verified).order(:verified_at).last
    return if verified.nil? || verified.iban == Accounting::Iban.normalize(invoice.iban)

    fingerprint = "invoice_iban:#{invoice.id}"
    return if Accounting::Task.exists?(anomaly_fingerprint: fingerprint)

    task = Accounting::Task.create!(title: "IBAN on invoice #{invoice.invoice_number || invoice.external_ref} differs from the verified account of #{invoice.partner.name}",
                                    description: description(invoice, verified), kind: :to_check, priority: :high, target: invoice, anomaly_fingerprint: fingerprint)
    Accounting::AuditLog.record!(auditable: invoice, action: "invoice_iban_differs", payload: { partner_id: invoice.partner_id, on_invoice: masked(invoice.iban), verified: verified.masked_iban, task_id: task.id })
    UserEntity.owners.current.where(entity_id: invoice.entity_id).includes(:user).each do |membership|
      Accounting::Notify.call(user: membership.user, event: "bank_account_invoice_mismatch:#{invoice.id}", subject: invoice, data: { message: invoice.partner.name })
    end
  end

  def self.description(invoice, verified)
    "The invoice says #{masked(invoice.iban)}; the verified account of the supplier is #{verified.masked_iban}. Nothing was changed. Call the supplier on a number you already had " \
      "(never the one on the invoice or in the message that announced the change); if the new account is genuine, register it: it will be observed and verified by someone else before any payment."
  end
  private_class_method :description

  def self.masked(iban) = Accounting::PartnerBankAccount.new(iban: iban).masked_iban
  private_class_method :masked
end
