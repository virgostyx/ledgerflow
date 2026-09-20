# Cancels a posted invoice by reversing its journal entry. Refused once money is involved (paid, receipts
# linked to it, or an active payment batch line): undo those first. All or nothing.
class Accounting::CancelInvoice
  def self.call(invoice:)
    ctx = LightService::Context.make(invoice: invoice)
    refusal = refusal_for(invoice)
    return ctx.tap { |c| c.fail!(refusal) } if refusal

    ApplicationRecord.transaction do
      reversed = Accounting::ReverseJournalEntry.call(entry: invoice.journal_entry, from_source: true)
      if reversed.failure?
        ctx.fail!(reversed.message)
        raise ActiveRecord::Rollback
      end

      invoice.cancel!
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}")
    ctx
  end

  def self.refusal_for(invoice)
    return I18n.t("accounting.invoices.errors.cancel_not_posted") unless invoice.posted? && invoice.journal_entry
    I18n.t("accounting.invoices.errors.cancel_paid") if invoice.paid_amount.positive? ||
                                                              Accounting::PaymentBatchLine.active.exists?(invoice_id: invoice.id)
  end
  private_class_method :refusal_for
end
