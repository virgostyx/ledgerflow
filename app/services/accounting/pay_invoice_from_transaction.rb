# Settles a posted supplier invoice with a pending bank debit, typically on a foreign account where no SEPA batch
# exists. The bank is credited and 440000 debited for `eur_amount` (the EUR value actually moved; defaults to the
# transaction amount on an EUR account).
# - Whole invoice (no `invoice_amount`): lettered with the invoice, a rate difference becomes an FX entry.
# - Deposit (`invoice_amount` < what is left, in the invoice currency), or any payment once a deposit exists: the
#   movement is allocated to the part it settles. The booked share of that part is prorated (the last payment takes
#   whatever is left); `eur_amount` minus that share is the realized exchange difference, booked at once. The invoice
#   is partially paid until the group is fully allocated, then lettered and paid.
class Accounting::PayInvoiceFromTransaction
  SUPPLIERS = Accounting::AccountCodes::SUPPLIERS

  def self.call(transaction:, invoice:, fiscal_year:, eur_amount: nil, invoice_amount: nil)
    ctx = LightService::Context.make(transaction: transaction, invoice: invoice)
    eur_amount ||= transaction.amount.abs if transaction.bank_account.currency == "EUR"
    trade     = invoice.journal_entry&.lines&.find_by(account: Accounting::Account.find_by(code: SUPPLIERS))
    remaining = remaining_in_invoice_currency(invoice, trade)
    partial   = trade&.allocations&.exists? || (invoice_amount.present? && invoice_amount < remaining)
    invoice_amount = partial ? (invoice_amount || remaining) : nil

    error = guard(transaction, invoice, eur_amount, invoice_amount, remaining, partial)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.bank_reconciliation.pay_errors.#{error}")) } if error

    ApplicationRecord.transaction do
      pay(ctx, transaction, invoice, trade, fiscal_year, eur_amount, invoice_amount, remaining)
      raise ActiveRecord::Rollback if ctx.failure?
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}") unless ctx.failure?
    ctx
  end

  def self.remaining_in_invoice_currency(invoice, trade)
    return invoice.total_incl_vat unless trade

    settled = Accounting::JournalEntryLine.where(invoice_id: invoice.id).where.not(id: trade.id).where("debit > 0")
                                          .sum("COALESCE(amount_currency, debit)")
    invoice.total_incl_vat - settled
  end

  def self.guard(tx, invoice, eur_amount, invoice_amount, remaining, partial)
    expected = partial ? invoice_amount : invoice.total_incl_vat
    if !(tx.pending? && tx.debit?)                                                  then "not_pending_debit"
    elsif !(invoice.supplier? && invoice.invoice? && (invoice.posted? || invoice.partially_paid?)) then "not_open_supplier_invoice"
    elsif eur_amount.nil? || eur_amount <= 0                                        then "eur_amount_required"
    elsif partial && (invoice_amount <= 0 || invoice_amount > remaining)            then "invoice_amount_out_of_range"
    elsif tx.currency == invoice.currency && tx.amount.abs != expected              then "amount_mismatch"
    end
  end
  private_class_method :remaining_in_invoice_currency, :guard

  def self.pay(ctx, tx, invoice, invoice_line, fiscal_year, eur_amount, invoice_amount, remaining)
    trade = invoice_line.account
    part  = invoice_amount || invoice.total_incl_vat
    label = tx.description.presence || invoice.partner.name
    foreign = ->(currency, amount) { currency == "EUR" ? {} : { currency: currency, amount_currency: amount, exchange_rate: (eur_amount / amount).round(6) } }

    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    entry = Accounting::JournalEntry.create!(
      journal: tx.bank_account.journal, fiscal_year: fiscal_year, entry_date: tx.transaction_date,
      description: "Payment #{invoice.invoice_number} — #{invoice.partner.name}", status: :draft
    )
    payment_line = Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: trade, partner: invoice.partner, invoice: invoice, label: label,
      debit: eur_amount, credit: 0, **foreign.(invoice.currency, part)
    )
    Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: tx.bank_account.journal.default_account, label: label,
      debit: 0, credit: eur_amount, **foreign.(tx.currency, tx.amount.abs)
    )

    posted = Accounting::PostJournalEntry.call(entry: entry)
    return ctx.fail!(posted.message) if posted.failure?

    tx.update!(status: :reconciled, journal_entry: entry)
    lines = invoice_amount ? allocate_part(ctx, invoice, invoice_line, payment_line, fiscal_year, tx, eur_amount, invoice_amount, remaining) : nil
    return if ctx.failure?

    if lines
      settle_group(ctx, lines)
    else
      lettered = Accounting::LetterLines.call(lines: [ invoice_line, payment_line.reload ])
      ctx.fail!(lettered.message) if lettered.failure?
    end
  end
  private_class_method :pay

  # Allocates the payment to its booked share of the invoice; the rate difference is booked on a separate FX entry whose
  # trade line takes part in the allocation (credit when we paid more than the share, debit when less).
  def self.allocate_part(ctx, invoice, invoice_line, payment_line, fiscal_year, tx, eur_amount, invoice_amount, remaining)
    share = invoice_amount == remaining ? invoice_line.open_amount : ((invoice_line.debit + invoice_line.credit) * invoice_amount / invoice.total_incl_vat).round(2)
    diff  = eur_amount - share
    fx_line = diff.zero? ? nil : post_fx(ctx, invoice, invoice_line, fiscal_year, tx.transaction_date, diff)
    return if ctx.failure?

    allocate = ->(debit, credit, amount) { Accounting::LineAllocation.create!(debit_line: debit, credit_line: credit, amount: amount, allocated_on: tx.transaction_date) }
    if diff.positive?
      allocate.(payment_line, fx_line, diff)
      allocate.(payment_line, invoice_line, share)
    else
      allocate.(payment_line, invoice_line, eur_amount)
      allocate.(fx_line, invoice_line, -diff) if fx_line
    end
    lines = [ invoice_line, payment_line, fx_line ].compact
    Accounting::JournalEntryLine.resync_amount_residual!(lines.map(&:id))
    lines
  end
  private_class_method :allocate_part

  # Same bookkeeping as Accounting::Actions::PostFxAdjustment, for one payment: loss => credit on 440000, gain => debit.
  def self.post_fx(ctx, invoice, invoice_line, fiscal_year, date, diff)
    journal = Accounting::Journal.where(journal_type: :misc, active: true).first
    return ctx.fail!("No active misc journal found for the FX adjustment entry.") unless journal

    loss = diff.positive?
    entry = Accounting::JournalEntry.new(journal: journal, fiscal_year: fiscal_year, entry_date: date,
                                         description: "FX adjustment — #{invoice_line.account.code}", status: :draft)
    entry.reference = journal.next_sequence_number(year: date.year)
    entry.save!
    zero = BigDecimal("0")
    amount = diff.abs
    trade_line = Accounting::JournalEntryLine.create!(journal_entry: entry, account: invoice_line.account, partner: invoice.partner,
                                                      debit: loss ? zero : amount, credit: loss ? amount : zero, label: "FX adjustment")
    Accounting::JournalEntryLine.create!(journal_entry: entry, account: Accounting::Account.find_by!(code: loss ? Accounting::AccountCodes::FX_LOSS : Accounting::AccountCodes::FX_GAIN),
                                         debit: loss ? amount : zero, credit: loss ? zero : amount, label: "FX adjustment")
    entry.post!
    trade_line
  end
  private_class_method :post_fx

  # Everything linked is fully allocated: close the group into a lettering (which pays the invoice); otherwise reflect the part.
  def self.settle_group(ctx, lines)
    group = Accounting::LineAllocation.group_lines(lines)
    if group.all? { |l| l.open_amount.zero? }
      lettered = Accounting::LetterLines.call(lines: group)
      ctx.fail!(lettered.message) if lettered.failure?
    else
      Accounting::SyncInvoiceStatus.call(group)
    end
  end
  private_class_method :settle_group
end
