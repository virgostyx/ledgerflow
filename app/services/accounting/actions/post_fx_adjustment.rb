# When a foreign-currency invoice line is lettered against an EUR payment line, a rate move
# between invoice date and payment date leaves the group unbalanced in EUR. This posts the
# realized FX gain/loss (751100/651200) and tops up the trade account line to close the gap,
# so the normal debit == credit lettering check passes unchanged.
class Accounting::Actions::PostFxAdjustment
  extend LightService::Action

  expects  :lines
  promises :lines

  executed do |ctx|
    lines = ctx.lines
    ctx.lines = lines
    next unless lines.any? { |l| l.currency != "EUR" }

    diff = lines.sum(&:credit) - lines.sum(&:debit)
    next if diff.zero?

    first   = lines.first
    journal = Accounting::Journal.where(journal_type: :misc, active: true).first
    unless journal
      ctx.fail_with_rollback!("No active misc journal found for the FX adjustment entry.")
      next
    end

    entry = Accounting::JournalEntry.new(
      journal:     journal,
      fiscal_year: first.journal_entry.fiscal_year,
      entry_date:  Date.current,
      description: "FX adjustment — #{first.account.code}",
      status:      :draft
    )
    entry.reference = journal.next_sequence_number(year: Date.current.year)
    entry.save!

    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

    amount   = diff.abs
    gain     = diff.positive?
    fx_account = Accounting::Account.find_by!(code: gain ? Accounting::AccountCodes::FX_GAIN : Accounting::AccountCodes::FX_LOSS)
    zero = BigDecimal("0")

    trade_line = Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: first.account, partner: first.partner,
      debit:  gain ? amount : zero,
      credit: gain ? zero : amount,
      label:  "FX adjustment"
    )
    Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: fx_account,
      debit:  gain ? zero : amount,
      credit: gain ? amount : zero,
      label:  "FX adjustment"
    )

    entry.post!
    ctx.lines = lines + [ trade_line ]
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!("FX adjustment error: #{e.message}")
  end
end
