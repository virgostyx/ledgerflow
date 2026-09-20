# Invoice flagged as paid in cash: books the cash movement in the cash journal on the invoice date (supplier:
# Dr 440000 / Cr cash account; customer: Dr cash account / Cr 400000), then letters it with the invoice's trade
# line (which marks the invoice paid). No-op otherwise.
class Accounting::Actions::PayFromCash
  extend LightService::Action

  expects :invoice

  executed do |ctx|
    invoice = ctx.invoice
    next unless invoice.cash_journal

    customer = invoice.customer?
    trade    = Accounting::Account.find_by!(code: customer ? Accounting::AccountCodes::CUSTOMERS : Accounting::AccountCodes::SUPPLIERS)
    invoice_line = invoice.journal_entry.lines.find_by!(account: trade)
    total = invoice.total_incl_vat
    label = invoice.partner.name

    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    entry = Accounting::JournalEntry.create!(
      journal: invoice.cash_journal, fiscal_year: invoice.fiscal_year, entry_date: invoice.invoice_date,
      description: "Cash #{customer ? 'receipt' : 'payment'} #{invoice.invoice_number} — #{label}",
      status: :draft, source_type: "Accounting::Invoice"
    )
    trade_line = Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: trade, partner: invoice.partner, invoice: invoice, label: label,
      debit: customer ? 0 : total, credit: customer ? total : 0
    )
    Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: invoice.cash_journal.default_account, label: label,
      debit: customer ? total : 0, credit: customer ? 0 : total
    )

    posted = Accounting::PostJournalEntry.call(entry: entry)
    next ctx.fail_with_rollback!(posted.message) if posted.failure?

    lettered = Accounting::LetterLines.call(lines: [ invoice_line, trade_line ])
    ctx.fail_with_rollback!(lettered.message) if lettered.failure?
  end
end
