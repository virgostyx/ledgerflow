# The accountant sends a draft received from a third party (BudgetFlow) back to the project manager, with a mandatory
# reason. The draft is cancelled and the third party is told through a `returned` event; it can send a corrected version
# afterwards (a new revision). Only drafts of API-managed documents: a posted one is reversed, not returned.
class Accounting::ReturnInvoice
  def self.call(invoice:, reason:)
    ctx = LightService::Context.make(invoice: invoice)
    error = refusal_for(invoice, reason)
    return ctx.tap { |c| c.fail!(error) } if error

    ApplicationRecord.transaction do
      invoice.cancel!
      Accounting::InvoiceEvent.record!(invoice, "returned", reason: reason.strip)
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}")
    ctx
  end

  def self.refusal_for(invoice, reason)
    return I18n.t("accounting.invoices.errors.return_not_external_draft") unless invoice.draft? && invoice.external_digest.present?

    I18n.t("accounting.invoices.errors.return_reason_required") if reason.to_s.strip.blank?
  end
  private_class_method :refusal_for
end
