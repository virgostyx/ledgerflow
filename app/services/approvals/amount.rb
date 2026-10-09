# What a purchase invoice is worth for the circuit: the sum of its lines incl. VAT (added up by the database; the header totals only exist once
# it is posted), in EUR at the rate of the invoice. Policies, the bulk threshold and the step-up threshold all compare this.
module Approvals::Amount
  def self.eur(invoice)
    Fx::Convert.to_eur(Accounting::InvoiceLine.unscope(:order).where(invoice_id: invoice.id).sum(:total_incl_vat), invoice.exchange_rate)
  end
end
