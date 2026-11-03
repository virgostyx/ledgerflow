# Cancels a posted invoice by reversing its journal entry. Refused once money is involved (paid, receipts
# linked to it, or an active payment batch line): undo those first. All or nothing.
class Accounting::CancelInvoice
  def self.call(invoice:)
    ctx = LightService::Context.make(invoice: invoice)
    refusal = refusal_for(invoice)
    return ctx.tap { |c| c.fail!(refusal) } if refusal

    ApplicationRecord.transaction do
      # what it settled of advances goes back first (the advance is free again): 440000 and 409000 as they were
      invoice.advance_allocations.select(&:journal_entry_id).each do |allocation|
        undone = Accounting::ReverseJournalEntry.call(entry: allocation.journal_entry, from_source: true, confirm_unletter: true, date: allocation.journal_entry.entry_date)
        next if undone.success?

        ctx.fail!(undone.message)
        raise ActiveRecord::Rollback
      end

      invoice.reload
      invoice.release! if invoice.partially_paid?
      invoice.reopen! if invoice.paid?
      reversed = Accounting::ReverseJournalEntry.call(entry: invoice.journal_entry, from_source: true, date: invoice.journal_entry.entry_date) # strict, as before F07
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
    return I18n.t("accounting.invoices.errors.cancel_not_posted") unless (invoice.posted? || invoice.settled_by_advances_only?) && invoice.journal_entry
    asset = Accounting::FixedAsset.find_by(invoice_line_id: invoice.lines.map(&:id))
    return I18n.t("accounting.invoices.errors.cancel_has_fixed_asset", description: asset.description) if asset

    return I18n.t("accounting.invoices.errors.cancel_advance_consumed") if invoice.consumptions.live.exists?
    return I18n.t("accounting.invoices.errors.cancel_credited") if invoice.credit_notes.where(status: %i[posted partially_paid paid]).exists?

    I18n.t("accounting.invoices.errors.cancel_paid") if invoice.paid_amount.positive? ||
                                                              Accounting::PaymentBatchLine.active.exists?(invoice_id: invoice.id)
  end
  private_class_method :refusal_for
end
