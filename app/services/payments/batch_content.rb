# What an approval of a payment batch is about (B01b): the account debited, the date, the totals, and each included payment (who, which account, how much, which
# invoices and what part of each). The IBAN is part of it, only through a digest: the fingerprint says nothing readable. The reference, the status and who prepared it do not count.
class Payments::BatchContent
  def self.call(batch)
    {
      bank_account_id: batch.bank_account_id,
      execution_date: batch.requested_execution_date.iso8601,
      total: batch.total.to_d.to_s("F"),
      payments_count: batch.payments_count,
      payments: batch.items.where(status: :included).includes(:item_invoices).map { |item| payment(item) }.sort_by(&:to_s)
    }
  end

  def self.payment(item)
    [ item.partner_id, Digest::SHA256.hexdigest(item.iban.to_s), item.amount.to_d.to_s("F"), item.remittance.to_s, item.end_to_end_id,
      item.item_invoices.map { |link| [ link.invoice_id, link.amount.to_d.to_s("F") ] }.sort ]
  end
  private_class_method :payment
end
