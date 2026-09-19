class Payments::Actions::CreateSettlementJournalEntry
  extend LightService::Action

  expects :payment_batch
  promises :journal_entry

  executed do |ctx|
    batch               = ctx.payment_batch
    bank_journal        = batch.bank_account.journal
    bank_account_record = bank_journal.default_account
    payable_account     = Accounting::Account.find_by!(code: "440000")
    fiscal_year         = Accounting::FiscalYear.current
    lines               = batch.lines.includes(invoice: :partner).to_a

    entry = Accounting::JournalEntry.new(
      journal:      bank_journal,
      fiscal_year:  fiscal_year,
      entry_date:   Date.current,
      description:  "Supplier payment batch ##{batch.id} settlement",
      status:       :draft,
      source_type:  "Accounting::PaymentBatch",
      source_id:    batch.id
    )
    entry.save!

    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

    lines.each do |line|
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       payable_account,
        partner:       line.invoice.partner,
        debit:         line.amount,
        credit:        BigDecimal("0"),
        label:         line.invoice.invoice_number
      )
    end

    Accounting::JournalEntryLine.create!(
      journal_entry: entry,
      account:       bank_account_record,
      debit:         BigDecimal("0"),
      credit:        lines.sum(&:amount),
      label:         "Payment batch ##{batch.id}"
    )

    post_result = Accounting::PostJournalEntry.call(entry: entry)
    unless post_result.success?
      ctx.fail!(post_result.message)
      next
    end

    ctx.journal_entry = entry.reload
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!(e.record.errors.full_messages.join(", "))
  end
end
