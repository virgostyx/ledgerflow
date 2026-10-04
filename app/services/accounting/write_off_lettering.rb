# F04 §7, rounding difference: lines of one account and partner that miss balancing by no more than the entity's tolerance
# (`bank_rounding_tolerance`) are closed with a draft entry on the rounding accounts (658100 charge, 758100 income). Nothing is
# lettered yet (a draft line cannot be): Actions::FinalizeLetteringWriteOff letters the lines, with the adjustment line, when the entry
# is validated. The entry is dated like the latest of the lines, in its fiscal year.
# => ctx[:entry], the draft
class Accounting::WriteOffLettering
  def self.call(lines:, user: nil)
    ctx = LightService::Context.make(lines: lines)
    lines = Accounting::JournalEntryLine.where(id: Array(lines).map(&:id)).order(:id).includes(:account, :partner, journal_entry: :fiscal_year).to_a
    ApplicationRecord.transaction do
      Accounting::PeriodLock.serialize_for_entity!
      difference = lines.sum(&:debit) - lines.sum(&:credit)
      error = problem(lines, difference)
      next ctx.fail!(error) if error

      journal = Accounting::Journal.find_by(journal_type: :misc, active: true)
      next ctx.fail!("No active misc journal found for the rounding entry.") unless journal

      entry = create_entry(journal, lines, difference)
      Accounting::LetteringWriteOff.create!(journal_entry: entry, line_ids: lines.map(&:id), created_by: user)
      ctx[:entry] = entry
    end
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!(e.message)
  end

  def self.problem(lines, difference)
    if lines.size < 2 then "Select at least two lines"
    elsif lines.any? { |l| !l.journal_entry.in_ledger? || l.lettering_id } then "Only open lines of posted entries can be written off"
    elsif lines.map(&:account_id).uniq.size > 1 then "Lines must be on the same account"
    elsif lines.map(&:partner_id).uniq.size > 1 then "Lines must have the same partner"
    elsif !Accounting::CreateRoundingAccounts.ready? then "The rounding accounts (658100, 758100) do not exist in this entity's chart"
    elsif difference.zero? then "The lines balance: letter them"
    elsif difference.abs > ActsAsTenant.current_tenant.bank_rounding_tolerance then "The difference is above the rounding tolerance"
    elsif Accounting::LetteringWriteOff.pending_for?(lines.map(&:id)) then "A rounding entry is already waiting for these lines"
    end
  end

  # Σ debit > Σ credit: the account is left with a debit, the adjustment credits it and charges 658100; the reverse earns 758100.
  def self.create_entry(journal, lines, difference)
    first   = lines.max_by { |l| l.journal_entry.entry_date }.journal_entry
    amount  = difference.abs
    charge  = difference.positive?
    entry = Accounting::JournalEntry.create!(journal: journal, fiscal_year: first.fiscal_year, entry_date: first.entry_date, status: :draft,
                                             description: "Rounding difference — #{lines.first.account.code}",
                                             reference: journal.next_sequence_number(year: first.entry_date.year))
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    zero = BigDecimal("0")
    rounding = Accounting::Account.find_by!(code: charge ? Accounting::AccountCodes::ROUNDING_LOSS : Accounting::AccountCodes::ROUNDING_GAIN)
    Accounting::JournalEntryLine.create!(journal_entry: entry, account: lines.first.account, partner: lines.first.partner,
                                         debit: charge ? zero : amount, credit: charge ? amount : zero, label: "Rounding difference")
    Accounting::JournalEntryLine.create!(journal_entry: entry, account: rounding,
                                         debit: charge ? amount : zero, credit: charge ? zero : amount, label: "Rounding difference")
    entry
  end
  private_class_method :problem, :create_entry
end
