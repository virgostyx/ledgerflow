class Accounting::Actions::GenerateInvoiceJournalEntry
  extend LightService::Action

  expects  :invoice
  promises :invoice

  # Belgian VAT grid codes — grilles de la déclaration TVA périodique belge
  # Purchase expense lines: base amount excl. VAT per rate
  VAT_GRID_PURCHASE = { 21 => 81, 12 => 82, 6 => 83 }.freeze
  # Sale revenue lines: base amount excl. VAT per rate
  VAT_GRID_SALE     = { 21 => 1, 12 => 2, 6 => 3 }.freeze
  # TVA code for the VAT journal entry lines
  VAT_CODE_PURCHASE_VAT = 59  # TVA récupérable (411000)
  VAT_CODE_SALE_VAT     = 54  # TVA à reverser (451000)

  executed do |ctx|
    invoice = ctx.invoice
    journal = find_journal(invoice)
    fiscal_year = invoice.fiscal_year

    entry = Accounting::JournalEntry.new(
      journal:      journal,
      fiscal_year:  fiscal_year,
      entry_date:   invoice.invoice_date,
      reference:    invoice.invoice_number,
      description:  "Invoice #{invoice.invoice_number} — #{invoice.partner.name}",
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
    return invoice.journal if invoice.journal.present?
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
      vat_code = VAT_GRID_SALE[line.vat_rate.to_i]
      journal_line = Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       line.account,
        debit:         BigDecimal("0"),
        credit:        line.subtotal_excl_vat,
        label:         line.description,
        vat_code:      vat_code
      )
      propagate_annotations(line, journal_line)
    end

    invoice.lines.group_by { |l| l.vat_rate.to_i }.each do |rate, lines|
      next if rate.zero?
      grouped_vat = lines.sum(&:vat_amount)
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       vat_account,
        debit:         BigDecimal("0"),
        credit:        grouped_vat,
        label:         "VAT #{rate}%",
        vat_code:      VAT_CODE_SALE_VAT,
        vat_amount:    grouped_vat
      )
    end
  end

  def self.build_supplier_lines(invoice, entry)
    payable_account = Accounting::Account.find_by!(code: "440000")
    vat_account     = Accounting::Account.find_by!(code: "411000")

    invoice.lines.each do |line|
      vat_code = VAT_GRID_PURCHASE[line.vat_rate.to_i]
      journal_line = Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       line.account,
        debit:         line.subtotal_excl_vat,
        credit:        BigDecimal("0"),
        label:         line.description,
        vat_code:      vat_code
      )
      propagate_annotations(line, journal_line)
    end

    invoice.lines.group_by { |l| l.vat_rate.to_i }.each do |rate, lines|
      next if rate.zero?
      grouped_vat = lines.sum(&:vat_amount)
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       vat_account,
        debit:         grouped_vat,
        credit:        BigDecimal("0"),
        label:         "Recoverable VAT #{rate}%",
        vat_code:      VAT_CODE_PURCHASE_VAT,
        vat_amount:    grouped_vat
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

  def self.propagate_annotations(invoice_line, journal_line)
    invoice_line.analytical_annotations.each do |ann|
      Accounting::AnalyticalAnnotation.create!(
        journal_entry_line: journal_line,
        analytical_axis:    ann.analytical_axis,
        analytical_account: ann.analytical_account
      )
    end
  end

  private_class_method :find_journal, :build_entry_lines,
                       :build_customer_lines, :build_supplier_lines,
                       :propagate_annotations
end
