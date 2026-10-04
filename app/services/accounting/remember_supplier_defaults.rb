# F06: once a supplier invoice is posted, the account of its largest line, its journal, its VAT treatment and the payment terms it gave are kept
# as the defaults of the supplier, to propose them on the next invoice received. Never on a line that still sits on the suspense account.
class Accounting::RememberSupplierDefaults
  def self.call(invoice:)
    return unless invoice.supplier? && invoice.invoice? && invoice.lines.any?

    line = invoice.lines.reject { |l| l.account.code == Accounting::AccountCodes::TRANSIT }.max_by(&:subtotal_excl_vat)
    return unless line

    terms = (invoice.due_date - invoice.invoice_date).to_i if invoice.due_date
    Accounting::SupplierDefault.find_or_initialize_by(partner_id: invoice.partner_id).update!(
      account: line.account, journal: invoice.journal, vat_treatment: invoice.vat_treatment, payment_terms_days: (terms if terms && terms >= 0)
    )
  end
end
