class Accounting::Actions::AssignInvoiceNumber
  extend LightService::Action

  expects  :invoice
  promises :invoice

  executed do |ctx|
    invoice = ctx.invoice
    journal = find_journal(invoice)

    if journal.nil?
      ctx.fail_with_rollback!(I18n.t("accounting.invoices.errors.no_journal",
                                     type: invoice.invoice_type))
      next
    end

    invoice.invoice_number = journal.next_sequence_number(year: invoice.invoice_date.year)
    invoice.save!
    ctx.invoice = invoice
  end

  def self.find_journal(invoice)
    journal_type = invoice.customer? ? :sale : :purchase
    Accounting::Journal.active.find_by(journal_type: journal_type)
  end
  private_class_method :find_journal
end
