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
    receivable_account = Accounting::Account.find_by!(code: Accounting::AccountCodes::CUSTOMERS)
    vat_account        = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_PAYABLE)

    create_line(entry, :debit, invoice.total_incl_vat, invoice: invoice, account: receivable_account,
                partner: invoice.partner, label: invoice.partner.name)
    build_item_lines(invoice, entry, :credit, VAT_GRID_SALE)
    build_vat_lines(invoice, entry, :credit, account: vat_account, vat_code: VAT_CODE_SALE_VAT, label: "VAT")
  end

  def self.build_supplier_lines(invoice, entry)
    payable_account = Accounting::Account.find_by!(code: Accounting::AccountCodes::SUPPLIERS)
    vat_account     = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_DEDUCTIBLE)

    build_item_lines(invoice, entry, :debit, VAT_GRID_PURCHASE)
    build_vat_lines(invoice, entry, :debit, account: vat_account, vat_code: VAT_CODE_PURCHASE_VAT, label: "Recoverable VAT")
    create_line(entry, :credit, invoice.total_incl_vat, invoice: invoice, account: payable_account,
                partner: invoice.partner, label: invoice.partner.name)
  end

  # One journal line per invoice line, on `side`, carrying the VAT grid code.
  def self.build_item_lines(invoice, entry, side, vat_grid)
    invoice.lines.each do |line|
      journal_line = create_line(entry, side, line.subtotal_excl_vat, invoice: invoice, account: line.account,
                                 label: line.description, vat_code: vat_grid[line.vat_rate.to_i])
      propagate_annotations(line, journal_line)
    end
  end

  # One VAT line per non-zero rate, on `side`.
  def self.build_vat_lines(invoice, entry, side, account:, vat_code:, label:)
    invoice.lines.group_by { |l| l.vat_rate.to_i }.each do |rate, lines|
      next if rate.zero?
      grouped_vat = lines.sum(&:vat_amount)
      create_line(entry, side, grouped_vat, invoice: invoice, account: account, label: "#{label} #{rate}%",
                  vat_code: vat_code, vat_amount: (grouped_vat * invoice.exchange_rate).round(2))
    end
  end

  # `amount` is in the invoice's currency; debit/credit are always posted in EUR.
  def self.create_line(entry, side, amount, invoice:, **attrs)
    zero = BigDecimal("0")
    eur_amount = (amount * invoice.exchange_rate).round(2)
    Accounting::JournalEntryLine.create!(
      journal_entry:   entry,
      debit:           side == :debit ? eur_amount : zero,
      credit:          side == :credit ? eur_amount : zero,
      currency:        invoice.currency,
      amount_currency: amount,
      exchange_rate:   invoice.exchange_rate,
      **attrs
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
                       :build_item_lines, :build_vat_lines, :create_line,
                       :propagate_annotations
end
