# Copies an invoice into a new draft dated today, in the open fiscal year, keeping the payment interval of the original:
# partner, type, journal, currency, VAT treatment, description, notes and every line with its analytical annotations.
# What belongs to the original document (number, entry, Peppol data, external reference, cash journal, credited
# invoice) is not copied. A credit note is not duplicated. All or nothing.
class Accounting::DuplicateInvoice
  def self.call(invoice:)
    ctx = LightService::Context.make(invoice: nil)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.invoices.errors.duplicate_credit_note")) } unless invoice.invoice?

    fiscal_year = Accounting::FiscalYear.current
    return ctx.tap { |c| c.fail!(I18n.t("accounting.invoices.errors.no_open_fiscal_year")) } unless fiscal_year

    ApplicationRecord.transaction do
      copy = Accounting::Invoice.create!(
        invoice.slice(:partner_id, :invoice_type, :journal_id, :currency, :exchange_rate, :vat_treatment, :description, :notes)
               .merge(fiscal_year: fiscal_year, invoice_date: Date.current, due_date: due_date_like(invoice))
      )
      invoice.lines.each { |line| copy_line(line, copy) }
      ctx[:invoice] = copy
    end
    ctx
  rescue StandardError => e
    ctx[:invoice] = nil
    ctx.tap { |c| c.fail!("Error: #{e.message}") }
  end

  # Same interval between invoice and due dates as the original; none when it had no due date (the partner's terms apply).
  def self.due_date_like(invoice)
    Date.current + (invoice.due_date - invoice.invoice_date).to_i if invoice.due_date
  end

  def self.copy_line(line, copy)
    new_line = line.dup.tap { |l| l.invoice = copy }
    new_line.save!
    line.analytical_annotations.each do |annotation|
      Accounting::InvoiceLineAnnotation.create!(invoice_line: new_line, analytical_axis: annotation.analytical_axis,
                                                analytical_account: annotation.analytical_account)
    end
  end

  private_class_method :due_date_like, :copy_line
end
