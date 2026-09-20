# Supplier invoice flagged as paid from cash: books Dr 440000 / Cr cash account in the cash journal on the invoice
# date, then letters it with the invoice's payable line (which marks the invoice paid). No-op otherwise.
class Accounting::Actions::PayFromCash
  extend LightService::Action

  expects :invoice

  executed do |ctx|
    invoice = ctx.invoice
    next unless invoice.cash_journal

    payable = Accounting::Account.find_by!(code: Accounting::AccountCodes::SUPPLIERS)
    invoice_line = invoice.journal_entry.lines.find_by!(account: payable)

    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    entry = Accounting::JournalEntry.create!(
      journal: invoice.cash_journal, fiscal_year: invoice.fiscal_year, entry_date: invoice.invoice_date,
      description: "Cash payment #{invoice.invoice_number} — #{invoice.partner.name}",
      status: :draft, source_type: "Accounting::Invoice"
    )
    label = invoice.partner.name
    payment_line = Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: payable, partner: invoice.partner, invoice: invoice,
      debit: invoice.total_incl_vat, credit: 0, label: label
    )
    Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: invoice.cash_journal.default_account,
      debit: 0, credit: invoice.total_incl_vat, label: label
    )

    posted = Accounting::PostJournalEntry.call(entry: entry)
    next ctx.fail_with_rollback!(posted.message) if posted.failure?

    lettered = Accounting::LetterLines.call(lines: [ invoice_line, payment_line ])
    ctx.fail_with_rollback!(lettered.message) if lettered.failure?
  end
end
