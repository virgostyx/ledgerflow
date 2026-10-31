# Settles several posted supplier invoices of one supplier (euros) with one pending bank debit: a grouped transfer.
# One entry: the bank credited, 440000 debited once per invoice for its total; each invoice is lettered with its own line.
# `draft: true`: the entry waits for validation, Actions::FinalizeBankMatch then letters and pays the invoices.
# ponytail: whole invoices only, in euros; a deposit or a foreign payment goes through PayInvoiceFromTransaction, one invoice at a time.
class Accounting::PayInvoicesFromTransaction
  SUPPLIERS = Accounting::AccountCodes::SUPPLIERS

  def self.call(transaction:, invoices:, fiscal_year:, draft: false)
    error = guard(transaction, invoices)
    return LightService::Context.make(transaction: transaction).tap { |c| c.fail!(I18n.t("accounting.bank_reconciliation.pay_errors.#{error}")) } if error

    ctx = LightService::Context.make(transaction: transaction)
    ApplicationRecord.transaction do
      pay(ctx, transaction, invoices, fiscal_year, draft)
      raise ActiveRecord::Rollback if ctx.failure?
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}") unless ctx&.failure?
    ctx
  end

  def self.guard(tx, invoices)
    if !(tx.pending? && tx.debit?) || tx.currency != "EUR"                                     then "group_not_pending_debit"
    elsif invoices.size < 2 || invoices.uniq.size != invoices.size                             then "group_needs_invoices"
    elsif invoices.any? { |i| !(i.supplier? && i.invoice? && i.posted? && i.currency == "EUR") } then "not_open_supplier_invoice"
    elsif invoices.map(&:partner_id).uniq.size > 1                                             then "group_same_supplier"
    elsif invoices.sum(&:total_incl_vat) != tx.amount.abs                                      then "group_amount_mismatch"
    end
  end
  private_class_method :guard

  def self.pay(ctx, tx, invoices, fiscal_year, draft)
    suppliers = Accounting::Account.find_by!(code: SUPPLIERS)
    label     = tx.description.presence || invoices.first.partner.name
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    entry = Accounting::JournalEntry.create!(journal: tx.bank_account.journal, fiscal_year: fiscal_year, entry_date: tx.transaction_date, status: :draft,
                                             description: "Payment #{invoices.filter_map(&:invoice_number).join(', ')} — #{invoices.first.partner.name}")
    payments = invoices.map do |invoice|
      Accounting::JournalEntryLine.create!(journal_entry: entry, account: suppliers, partner: invoice.partner, invoice: invoice, label: label, debit: invoice.total_incl_vat, credit: 0)
    end
    Accounting::JournalEntryLine.create!(journal_entry: entry, account: tx.bank_account.journal.default_account, label: label, debit: 0, credit: tx.amount.abs)

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
  private_class_method :pay
end
