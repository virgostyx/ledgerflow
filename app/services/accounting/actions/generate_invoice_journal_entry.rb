class Accounting::Actions::GenerateInvoiceJournalEntry
  extend LightService::Action

  expects  :invoice
  promises :invoice

  VAT_GRID_PURCHASE     = Accounting::VatGrid::RATE_TO_GRID[:purchase]
  VAT_GRID_SALE         = Accounting::VatGrid::RATE_TO_GRID[:sale]
  VAT_CODE_PURCHASE_VAT = Accounting::VatGrid::VAT_LINE_GRID[:purchase]  # 410100
  VAT_CODE_SALE_VAT     = Accounting::VatGrid::VAT_LINE_GRID[:sale]      # 450100

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

    create_line(entry, :debit, invoice.total_incl_vat, invoice: invoice, account: receivable_account,
                partner: invoice.partner, label: invoice.partner.name)
    build_item_lines(invoice, entry, :credit, sale_grid(invoice))

    return unless invoice.domestic? # otherwise the partner self-assesses, or nothing is due

    vat_account = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_PAYABLE)
    build_vat_lines(invoice, entry, :credit, account: vat_account, vat_code: VAT_CODE_SALE_VAT, label: "VAT")
  end

  def self.build_supplier_lines(invoice, entry)
    payable_account = Accounting::Account.find_by!(code: Accounting::AccountCodes::SUPPLIERS)

    build_item_lines(invoice, entry, :debit, purchase_grid(invoice))
    build_supplier_vat_lines(invoice, entry)
    create_line(entry, :credit, invoice.total_incl_vat, invoice: invoice, account: payable_account,
                partner: invoice.partner, label: invoice.partner.name)
  end

  def self.build_supplier_vat_lines(invoice, entry)
    unless invoice.domestic?
      due_grid = Accounting::VatGrid::SELF_ASSESSED_VAT_GRID[invoice.vat_treatment.to_sym]
      if due_grid
        due_account = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_PAYABLE)
        build_vat_lines(invoice, entry, :credit, account: due_account, vat_code: due_grid,
                        label: "Self-assessed VAT due")
      end
      return unless due_grid # e.g. export: not a reverse-charge treatment, nothing to self-assess
    end

    build_deductible_vat_lines(invoice, entry)
  end

  # Recoverable VAT, split by the entity's deduction prorata (nil = fully deductible,
  # the pre-Phase-5 default). The non-recoverable share is posted as a plain cost,
  # outside any VAT grid.
  def self.build_deductible_vat_lines(invoice, entry)
    deductible_account = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_DEDUCTIBLE)
    prorata = invoice.entity.franchise? ? 0 : invoice.entity.vat_prorata_rate # a franchise recovers nothing

    invoice.lines.group_by { |l| l.vat_rate.to_i }.each do |rate, lines|
      next if rate.zero?
      grouped_vat = lines.sum(&:vat_amount)
      deductible  = prorata.present? ? (grouped_vat * prorata / 100).round(2) : grouped_vat

      if deductible.positive?
        create_line(entry, :debit, deductible, invoice: invoice, account: deductible_account,
                    label: "Recoverable VAT #{rate}%", vat_code: VAT_CODE_PURCHASE_VAT,
                    vat_amount: (deductible * invoice.exchange_rate).round(2))
      end

      non_deductible = grouped_vat - deductible
      next unless non_deductible.positive?

      non_deductible_account = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_NON_DEDUCTIBLE)
      create_line(entry, :debit, non_deductible, invoice: invoice, account: non_deductible_account,
                  label: "Non-deductible VAT #{rate}%")
    end
  end

  # Rate-based grids for domestic invoices; a single fixed grid (any rate) otherwise.
  def self.sale_grid(invoice)
    return VAT_GRID_SALE if invoice.domestic?
    Hash.new(Accounting::VatGrid::TREATMENT_BASE_GRID[:sale][invoice.vat_treatment.to_sym])
  end

  def self.purchase_grid(invoice)
    return VAT_GRID_PURCHASE if invoice.domestic?
    Hash.new(Accounting::VatGrid::TREATMENT_BASE_GRID[:purchase][invoice.vat_treatment.to_sym])
  end

  # One journal line per invoice line, on `side`, carrying the VAT grid code.
  def self.build_item_lines(invoice, entry, side, vat_grid)
    invoice.lines.each do |line|
      journal_line = create_line(entry, side, line.subtotal_excl_vat, invoice: invoice, account: line.account,
                                 label: line.description, vat_code: vat_grid[line.vat_rate.to_i],
                                 vat_amount: (line.subtotal_excl_vat * invoice.exchange_rate).round(2))
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
  # A credit note mirrors its invoice: sides are swapped and grid amounts negated, so grids net out.
  def self.create_line(entry, side, amount, invoice:, **attrs)
    if invoice.credit_note?
      side = side == :debit ? :credit : :debit
      attrs[:vat_amount] = -attrs[:vat_amount] if attrs[:vat_amount]
    end
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
                       :build_customer_lines, :build_supplier_lines, :build_supplier_vat_lines,
                       :build_deductible_vat_lines, :sale_grid, :purchase_grid,
                       :build_item_lines, :build_vat_lines, :create_line,
                       :propagate_annotations
end
