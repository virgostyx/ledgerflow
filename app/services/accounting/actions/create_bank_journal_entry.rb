class Accounting::Actions::CreateBankJournalEntry
  extend LightService::Action

  expects :transaction, :account_id, :fiscal_year
  promises :journal_entry

  executed do |ctx|
    tx          = ctx.transaction
    bank_acct   = tx.bank_account
    bank_journal = bank_acct.journal
    bank_account_record = bank_journal.default_account
    counterpart = Accounting::Account.find(ctx.account_id)
    abs_amount  = tx.amount.abs
    label       = ctx.respond_to?(:label) ? ctx[:label].presence : tx.description

    debit_account  = tx.credit? ? bank_account_record : counterpart
    credit_account = tx.credit? ? counterpart          : bank_account_record

    entry = nil
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

    entry = Accounting::JournalEntry.create!(
      journal:     bank_journal,
      fiscal_year: ctx.fiscal_year,
      entry_date:  tx.transaction_date,
      description: label || tx.description,
      status:      :draft
    )

    Accounting::JournalEntryLine.create!(
      journal_entry: entry,
      account:       debit_account,
      debit:         abs_amount,
      credit:        BigDecimal("0"),
      label:         label || tx.description
    )

    Accounting::JournalEntryLine.create!(
      journal_entry: entry,
      account:       credit_account,
      debit:         BigDecimal("0"),
      credit:        abs_amount,
      label:         label || tx.description
    )

    post_result = Accounting::PostJournalEntry.call(entry: entry)
    unless post_result.success?
      ctx.fail_with_rollback!(post_result.message)
      next
    end

    ctx.journal_entry = entry.reload
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!(e.record.errors.full_messages.join(", "))
  end
end
