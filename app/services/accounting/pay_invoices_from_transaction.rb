# Settles several posted supplier invoices of one supplier with one pending bank debit: a grouped transfer.
# One entry: the bank credited, 440000 debited once per invoice for its total; each invoice is lettered with its own line.
# In a foreign currency (invoices and movement in the same one), the bank knows no euro: `eur_amount` is the conversion the person confirms, shared between the
# invoices in proportion to their totals (the last takes the cents left); the lettering books the exchange difference of each invoice.
# `draft: true`: the entry waits for validation, Actions::FinalizeBankMatch then letters and pays the invoices (euros only).
# ponytail: whole invoices only; a deposit goes through PayInvoiceFromTransaction, one invoice at a time.
class Accounting::PayInvoicesFromTransaction
  SUPPLIERS = Accounting::AccountCodes::SUPPLIERS

  def self.call(transaction:, invoices:, fiscal_year:, draft: false, eur_amount: nil)
    eur_amount ||= transaction.amount.abs if transaction.bank_account.currency == "EUR"
    error = guard(transaction, invoices, eur_amount, draft)
    return LightService::Context.make(transaction: transaction).tap { |c| c.fail!(I18n.t("accounting.bank_reconciliation.pay_errors.#{error}")) } if error

    ctx = LightService::Context.make(transaction: transaction)
    ApplicationRecord.transaction do
      pay(ctx, transaction, invoices, fiscal_year, draft, eur_amount)
      raise ActiveRecord::Rollback if ctx.failure?
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}") unless ctx&.failure?
    ctx
  end

  def self.guard(tx, invoices, eur_amount, draft)
    if !(tx.pending? && tx.debit?)                                                             then "group_not_pending_debit"
    elsif invoices.size < 2 || invoices.uniq.size != invoices.size                             then "group_needs_invoices"
    elsif invoices.any? { |i| !(i.supplier? && i.payable_document? && i.posted?) }                      then "not_open_supplier_invoice"
    elsif invoices.any? { |i| i.currency != tx.currency }                                      then "group_currency_mismatch"
    elsif invoices.map(&:partner_id).uniq.size > 1                                             then "group_same_supplier"
    elsif invoices.sum(&:total_incl_vat) != tx.amount.abs                                      then "group_amount_mismatch"
    elsif eur_amount.nil? || eur_amount <= 0                                                   then "eur_amount_required"
    elsif draft && tx.currency != "EUR"                                                        then "draft_unsupported"
    end
  end
  private_class_method :guard

  def self.pay(ctx, tx, invoices, fiscal_year, draft, eur_amount)
    suppliers = Accounting::Account.find_by!(code: SUPPLIERS)
    label     = tx.description.presence || invoices.first.partner.name
    shares    = eur_shares(invoices, eur_amount)
    foreign   = ->(currency, amount, eur, sign) { currency == "EUR" ? {} : { currency: currency, amount_currency: sign * amount, exchange_rate: (amount / eur).round(8) } }
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    entry = Accounting::JournalEntry.create!(journal: tx.bank_account.journal, fiscal_year: fiscal_year, entry_date: tx.transaction_date, status: :draft,
                                             description: "Payment #{invoices.filter_map(&:invoice_number).join(', ')} — #{invoices.first.partner.name}")
    payments = invoices.zip(shares).map do |invoice, share|
      Accounting::JournalEntryLine.create!(journal_entry: entry, account: suppliers, partner: invoice.partner, invoice: invoice, label: label, debit: share, credit: 0,
                                           **foreign.(invoice.currency, invoice.total_incl_vat, share, 1))
    end
    Accounting::JournalEntryLine.create!(journal_entry: entry, account: tx.bank_account.journal.default_account, label: label, debit: 0, credit: eur_amount,
                                         **foreign.(tx.currency, tx.amount.abs, eur_amount, -1))

    if draft
      tx.update!(status: :matched, journal_entry: entry)
      return
    end

    posted = Accounting::PostJournalEntry.call(entry: entry)
    return ctx.fail!(posted.message) if posted.failure?

    tx.update!(status: :reconciled, journal_entry: entry)
    invoices.zip(payments).each do |invoice, payment|
      lettered = Accounting::LetterLines.call(lines: [ invoice.journal_entry.lines.find_by!(account: suppliers), payment.reload ])
      return ctx.fail!(lettered.message) if lettered.failure?
    end
  end

  # What each invoice takes of the EUR amount: its share of the totals, to the cent; the last invoice takes what is left, so the shares add up exactly.
  def self.eur_shares(invoices, eur_amount)
    total  = invoices.sum(&:total_incl_vat)
    shares = invoices[0...-1].map { |i| (eur_amount * i.total_incl_vat / total).round(2) }
    shares + [ eur_amount - shares.sum ]
  end
  private_class_method :pay, :eur_shares
end
