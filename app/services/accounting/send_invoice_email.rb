# Queues the e-mailing of an issued customer invoice or credit note (PDF attached): records the attempt, then lets
# Accounting::InvoiceEmailJob deliver it.
class Accounting::SendInvoiceEmail
  def self.call(invoice:, recipient:, user:)
    ctx = LightService::Context.make(invoice: invoice, email: nil)
    error = refusal_for(invoice)
    return ctx.tap { |c| c.fail!(error) } if error

    email = Accounting::InvoiceEmail.new(invoice: invoice, sent_by: user, recipient: recipient.to_s.strip,
                                         subject: subject_for(invoice))
    return ctx.tap { |c| c.fail!(email.errors.full_messages.to_sentence) } unless email.save

    Accounting::InvoiceEmailJob.perform_later(email.id)
    ctx[:email] = email
    ctx
  end

  def self.refusal_for(invoice)
    return I18n.t("accounting.invoices.errors.email_customer_only") unless invoice.customer?

    I18n.t("accounting.invoices.errors.email_not_issued") unless invoice.issued?
  end

  def self.subject_for(invoice)
    "#{invoice.credit_note? ? 'Credit note' : 'Invoice'} #{invoice.invoice_number} from #{invoice.entity.legal_name}"
  end
  private_class_method :refusal_for, :subject_for
end
