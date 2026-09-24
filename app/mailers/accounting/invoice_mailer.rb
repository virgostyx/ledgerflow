class Accounting::InvoiceMailer < ApplicationMailer
  # Sender address: MAILER_FROM once a real SMTP is configured; the placeholder only makes sense in dev/test.
  FROM_ADDRESS = ENV.fetch("MAILER_FROM", "invoices@ledgerflow.example")

  def invoice_email(email)
    @invoice = email.invoice
    @entity  = email.entity

    # The PDF reads the issuer and bank account of the tenant; a job runs without one.
    pdf = ActsAsTenant.with_tenant(@entity) { Accounting::InvoicePdf.new(@invoice).render }
    attachments["#{@invoice.invoice_number.tr('/', '-')}.pdf"] = { mime_type: "application/pdf", content: pdf }

    mail(to: email.recipient, subject: email.subject, from: email_address_with_name(FROM_ADDRESS, @entity.legal_name))
  end
end
