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

    entry = nil
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

    entry = Accounting::JournalEntry.create!(
      journal:     bank_journal,
      fiscal_year: ctx.fiscal_year,
      entry_date:  tx.transaction_date,
      description: label || tx.description,
      status:      :draft
    )

    # One bank line for the whole transaction; the counterpart side is split per invoice when allocations are given.
    counterpart_lines = ctx[:allocations].presence || [ [ nil, abs_amount ] ]
    bank_side         = tx.credit? ? :debit : :credit
    counterpart_side  = tx.credit? ? :credit : :debit
    zero              = BigDecimal("0")

    Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: bank_account_record, label: label || tx.description,
      bank_side => abs_amount, counterpart_side => zero
    )
    counterpart_lines.each do |invoice, amount|
      Accounting::JournalEntryLine.create!(
        journal_entry: entry, account: counterpart, label: label || tx.description,
        partner: invoice&.partner, invoice: invoice,
        counterpart_side => amount, bank_side => zero
      )
    end

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
