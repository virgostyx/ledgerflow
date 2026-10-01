# The accountant sends an invoice received from a third party (BudgetFlow) back to the project manager, with a mandatory
# reason, so it can be corrected or dropped there. A draft is simply cancelled; a posted one has its entry reversed (the
# usual refusals apply: payments, payment batch, credit notes, fixed assets). The third party is told through a `returned`
# event and can send a corrected version afterwards (a new revision). This is the only way an API invoice is undone once
# handed over: the third party can neither correct nor delete it.
class Accounting::ReturnInvoice
  def self.call(invoice:, reason:)
    ctx = LightService::Context.make(invoice: invoice)
    error = refusal_for(invoice, reason)
    return ctx.tap { |c| c.fail!(error) } if error

    ApplicationRecord.transaction(requires_new: true) do
      done = cancel(invoice, reason.strip)
      if done.failure?
        ctx.fail!(done.message)
        raise ActiveRecord::Rollback
      end
      Accounting::InvoiceEvent.record!(invoice.reload, "returned", reason: reason.strip)
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}")
    ctx
  end

  def self.refusal_for(invoice, reason)
    return I18n.t("accounting.invoices.errors.return_not_external_draft") unless invoice.external_digest.present? && (invoice.draft? || invoice.posted?)

    I18n.t("accounting.invoices.errors.return_reason_required") if reason.to_s.strip.blank?
  end

  # The reason also goes to the audit trail of the reversal (R18).
  def self.cancel(invoice, reason)
    if invoice.draft?
      invoice.cancel!
      return LightService::Context.make(invoice: invoice)
    end

    Current.reason = reason
    Accounting::CancelInvoice.call(invoice: invoice)
  ensure
    Current.reason = nil
  end
  private_class_method :refusal_for, :cancel
end
