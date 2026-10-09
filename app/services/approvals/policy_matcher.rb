# Which approval policy applies to a purchase invoice (B01a): the first active one, by priority, whose conditions all hold.
# Conditions (jsonb): min_amount / max_amount (incl. VAT, in EUR, bounds included), partner_ids, account_ids (any line),
# project_ids, currencies, document_types (invoice, credit_note), first_payment (the supplier was never paid).
class Approvals::PolicyMatcher
  def self.call(invoice) = new(invoice).call

  def initialize(invoice)
    @invoice = invoice
  end

  def call
    Approvals::Policy.active.purchase_invoice.by_priority.detect { |policy| matches?(policy.conditions) }
  end

  private

  def matches?(c)
    amount_ok?(c) &&
      listed?(c["partner_ids"], @invoice.partner_id) &&
      listed?(c["project_ids"], @invoice.project_id) &&
      listed?(c["currencies"], @invoice.currency) &&
      listed?(c["document_types"], @invoice.document_type) &&
      account_ok?(c["account_ids"]) &&
      first_payment_ok?(c["first_payment"])
  end

  def amount_ok?(c)
    (c["min_amount"].blank? || amount >= c["min_amount"].to_d) && (c["max_amount"].blank? || amount <= c["max_amount"].to_d)
  end

  def listed?(list, value) = list.blank? || list.include?(value)

  def account_ok?(ids) = ids.blank? || @invoice.lines.where(account_id: ids).exists?

  # Never paid by us: no earlier invoice of this supplier is paid.
  def first_payment_ok?(wanted)
    wanted.blank? || !Accounting::Invoice.supplier.paid.where(partner_id: @invoice.partner_id).where.not(id: @invoice.id).exists?
  end

  # The amount including VAT, summed by the database, converted at the invoice's own rate.
  def amount
    @amount ||= Fx::Convert.to_eur(@invoice.lines.sum(:total_incl_vat), @invoice.exchange_rate)
  end
end
