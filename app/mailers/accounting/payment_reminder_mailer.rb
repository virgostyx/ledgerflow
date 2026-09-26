class Accounting::PaymentReminderMailer < ApplicationMailer
  def payment_reminder(reminder)
    @reminder = reminder
    @entity   = reminder.entity
    @items    = reminder.items.includes(:invoice).sort_by { |item| item.invoice.due_date }
    @sent_on  = reminder.created_at.to_date

    # The PDFs read the issuer and bank account of the tenant; a job runs without one.
    ActsAsTenant.with_tenant(@entity) do
      @items.each do |item|
        invoice = item.invoice
        attachments["#{invoice.invoice_number.tr('/', '-')}.pdf"] = { mime_type: "application/pdf", content: Accounting::InvoicePdf.new(invoice).render }
      end
    end

    mail(to: reminder.recipient, subject: reminder.subject,
         from: email_address_with_name(Accounting::InvoiceMailer::FROM_ADDRESS, @entity.legal_name))
  end
end
