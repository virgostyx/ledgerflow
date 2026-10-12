# What a subject is worth for the circuit, in EUR. A purchase invoice: the sum of its lines incl. VAT (added up by the database; the header totals only exist once
# it is posted), at the rate of the invoice. A payment batch: its total. Policies, the bulk threshold and the step-up threshold all compare this.
module Approvals::Amount
  def self.eur(subject)
    return subject.total if subject.is_a?(Payments::Batch)

    Fx::Convert.to_eur(Accounting::InvoiceLine.unscope(:order).where(invoice_id: subject.id).sum(:total_incl_vat), subject.exchange_rate)
  end
end
