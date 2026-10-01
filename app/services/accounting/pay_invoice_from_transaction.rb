# Settles a posted supplier invoice with a pending bank debit, typically on a foreign account where no SEPA batch
# exists. The bank is credited and 440000 debited for `eur_amount` (the EUR value actually moved; defaults to the
# transaction amount on an EUR account), then lettered with the invoice: a rate difference becomes an FX entry.
class Accounting::PayInvoiceFromTransaction
  SUPPLIERS = Accounting::AccountCodes::SUPPLIERS

  def self.call(transaction:, invoice:, fiscal_year:, eur_amount: nil)
    ctx = LightService::Context.make(transaction: transaction, invoice: invoice)
    account = transaction.bank_account
    eur_amount ||= transaction.amount.abs if account.currency == "EUR"

    error = if !(transaction.pending? && transaction.debit?)                                    then "not_pending_debit"
    elsif !(invoice.supplier? && invoice.invoice? && invoice.posted?)                           then "not_open_supplier_invoice"
    elsif eur_amount.nil? || eur_amount <= 0                                                    then "eur_amount_required"
    elsif transaction.currency == invoice.currency && transaction.amount.abs != invoice.total_incl_vat then "amount_mismatch"
    end
    return ctx.tap { |c| c.fail!(I18n.t("accounting.bank_reconciliation.pay_errors.#{error}")) } if error

    ApplicationRecord.transaction do
      pay(ctx, transaction, invoice, fiscal_year, eur_amount)
      raise ActiveRecord::Rollback if ctx.failure?
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}") unless ctx.failure?
    ctx
  end

  def self.pay(ctx, tx, invoice, fiscal_year, eur_amount)
    trade = Accounting::Account.find_by!(code: SUPPLIERS)
    invoice_line = invoice.journal_entry.lines.find_by!(account: trade)
    label = tx.description.presence || invoice.partner.name
    foreign = ->(currency, amount) { currency == "EUR" ? {} : { currency: currency, amount_currency: amount, exchange_rate: (eur_amount / amount).round(6) } }

    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    entry = Accounting::JournalEntry.create!(
      journal: tx.bank_account.journal, fiscal_year: fiscal_year, entry_date: tx.transaction_date,
      description: "Payment #{invoice.invoice_number} — #{invoice.partner.name}", status: :draft
    )
    payment_line = Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: trade, partner: invoice.partner, invoice: invoice, label: label,
      debit: eur_amount, credit: 0, **foreign.(invoice.currency, invoice.total_incl_vat)
    )
    Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: tx.bank_account.journal.default_account, label: label,
      debit: 0, credit: eur_amount, **foreign.(tx.currency, tx.amount.abs)
    )

    posted = Accounting::PostJournalEntry.call(entry: entry)
    return ctx.fail!(posted.message) if posted.failure?

    tx.update!(status: :reconciled, journal_entry: entry)
    lettered = Accounting::LetterLines.call(lines: [ invoice_line, payment_line.reload ])
    ctx.fail!(lettered.message) if lettered.failure?
  end
  private_class_method :pay
end
