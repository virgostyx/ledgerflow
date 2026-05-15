class Accounting::Actions::GenerateInvoiceJournalEntry
  extend LightService::Action

  expects  :invoice
  promises :invoice

  executed do |ctx|
    invoice = ctx.invoice
    journal = find_journal(invoice)
    fiscal_year = invoice.fiscal_year

    entry = Accounting::JournalEntry.new(
      journal:      journal,
      fiscal_year:  fiscal_year,
      entry_date:   invoice.invoice_date,
      reference:    invoice.invoice_number,
      description:  "Facture #{invoice.invoice_number} — #{invoice.partner.name}",
      status:       :draft,
      source_type:  "Accounting::Invoice"
    )
    entry.save!

    build_entry_lines(invoice, entry)

    entry.post!
    invoice.journal_entry = entry
    invoice.save!

    ctx.invoice = invoice
  end

  def self.find_journal(invoice)
    journal_type = invoice.customer? ? :sale : :purchase
    Accounting::Journal.active.find_by(journal_type: journal_type)
  end

  def self.build_entry_lines(invoice, entry)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

    if invoice.customer?
      build_customer_lines(invoice, entry)
    else
      build_supplier_lines(invoice, entry)
    end
  end

  def self.build_customer_lines(invoice, entry)
    receivable_account = Accounting::Account.find_by!(code: "400000")
    vat_account        = Accounting::Account.find_by!(code: "451000")

    Accounting::JournalEntryLine.create!(
      journal_entry: entry,
      account:       receivable_account,
      debit:         invoice.total_incl_vat,
      credit:        BigDecimal("0"),
      label:         invoice.partner.name
    )

    invoice.lines.each do |line|
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       line.account,
        debit:         BigDecimal("0"),
        credit:        line.subtotal_excl_vat,
        label:         line.description
      )
    end

    if invoice.vat_amount > BigDecimal("0")
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       vat_account,
        debit:         BigDecimal("0"),
        credit:        invoice.vat_amount,
        label:         "TVA"
      )
    end
  end

  def self.build_supplier_lines(invoice, entry)
    payable_account = Accounting::Account.find_by!(code: "440000")
    vat_account     = Accounting::Account.find_by!(code: "411000")

    invoice.lines.each do |line|
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       line.account,
        debit:         line.subtotal_excl_vat,
        credit:        BigDecimal("0"),
        label:         line.description
      )
    end

    if invoice.vat_amount > BigDecimal("0")
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       vat_account,
        debit:         invoice.vat_amount,
        credit:        BigDecimal("0"),
        label:         "TVA récupérable"
      )
    end

    Accounting::JournalEntryLine.create!(
      journal_entry: entry,
      account:       payable_account,
      debit:         BigDecimal("0"),
      credit:        invoice.total_incl_vat,
      label:         invoice.partner.name
    )
  end

  private_class_method :find_journal, :build_entry_lines,
                       :build_customer_lines, :build_supplier_lines
end
