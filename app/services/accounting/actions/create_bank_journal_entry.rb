class Accounting::Actions::CreateBankJournalEntry
  extend LightService::Action

  expects :transaction, :account_id, :fiscal_year
  promises :journal_entry

  executed do |ctx|
    tx          = ctx.transaction
    bank_acct   = tx.bank_account
    bank_journal = bank_acct.journal
    bank_account_record = bank_journal.default_account
    counterpart = Accounting::Account.find(ctx.account_id) if ctx.account_id.present?
    splits      = ctx[:splits].presence # [[account_id, amount], ...]: one movement booked on several accounts
    foreign     = tx.currency != "EUR"
    abs_amount  = foreign ? ctx[:eur_amount] : tx.amount.abs
    # A foreign-currency movement is booked from the EUR amount the accountant gives; allocations stay EUR-only.
    if foreign && (abs_amount.nil? || abs_amount <= 0 || ctx[:allocations].present?)
      ctx.fail_with_rollback!(I18n.t("accounting.bank_reconciliation.foreign_needs_eur_amount", currency: tx.currency))
      next
    end
    label       = ctx[:label].presence || tx.description

    entry = nil
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

    entry = Accounting::JournalEntry.create!(
      journal:     bank_journal,
      fiscal_year: ctx.fiscal_year,
      entry_date:  tx.transaction_date,
      description: label || tx.description,
      status:      :draft
    )

    if splits && splits.sum { |_, amount| amount } != abs_amount
      ctx.fail_with_rollback!(I18n.t("accounting.bank_reconciliation.splits_do_not_add_up", total: abs_amount.to_s("F")))
      next
    end

    # One bank line for the whole transaction; the counterpart side is split per invoice when allocations are given, per account when split.
    counterpart_lines = splits&.map { |account_id, amount| [ nil, amount, Accounting::Account.find(account_id) ] } || ctx[:allocations].presence || [ [ nil, abs_amount ] ]
    bank_side         = tx.credit? ? :debit : :credit
    counterpart_side  = tx.credit? ? :credit : :debit
    zero              = BigDecimal("0")

    foreign_attrs = foreign ? { currency: tx.currency, amount_currency: tx.amount.abs, exchange_rate: (abs_amount / tx.amount.abs).round(6) } : {}
    Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: bank_account_record, label: label || tx.description,
      bank_side => abs_amount, counterpart_side => zero, **foreign_attrs
    )
    counterpart_lines.each do |invoice, amount, account|
      Accounting::JournalEntryLine.create!(
        journal_entry: entry, account: account || counterpart, label: label || tx.description,
        partner: invoice&.partner || ctx[:partner], invoice: invoice,
        counterpart_side => amount, bank_side => zero
      )
    end
    # A receipt within the rounding tolerance: the invoice is settled whole, the few cents go to the rounding account.
    rounding = ctx[:rounding] || zero
    if rounding.nonzero?
      account = Accounting::Account.find_by(code: rounding.positive? ? Accounting::AccountCodes::ROUNDING_LOSS : Accounting::AccountCodes::ROUNDING_GAIN)
      Accounting::JournalEntryLine.create!(journal_entry: entry, account: account, label: label || tx.description,
                                           (rounding.positive? ? :debit : :credit) => rounding.abs, (rounding.positive? ? :credit : :debit) => zero)
    end

    # A draft stays a draft (F02: whoever cannot validate, and the exact automatic matches, produce drafts).
    unless ctx[:draft]
      post_result = Accounting::PostJournalEntry.call(entry: entry)
      unless post_result.success?
        ctx.fail_with_rollback!(post_result.message)
        next
      end
    end

    ctx.journal_entry = entry.reload
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!(e.record.errors.full_messages.join(", "))
  end
end
