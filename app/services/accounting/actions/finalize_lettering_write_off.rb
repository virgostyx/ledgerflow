# F04: validating the draft entry of a rounding difference letters the lines it waits for, with its own line on their account, as a
# write-off. A lettering that fails never undoes the validation: the lines stay open on the lettering screen.
class Accounting::Actions::FinalizeLetteringWriteOff
  extend LightService::Action

  expects :entry

  executed do |ctx|
    write_off = Accounting::LetteringWriteOff.pending.find_by(journal_entry_id: ctx.entry.id)
    next unless write_off

    account_id = Accounting::JournalEntryLine.where(id: write_off.line_ids).pick(:account_id)
    adjustment = ctx.entry.lines.find_by!(account_id: account_id)
    Accounting::LetterLines.call(lines: Accounting::JournalEntryLine.where(id: write_off.line_ids).to_a + [ adjustment ],
                                 user: write_off.created_by, kind: "write_off")
    write_off.update!(completed_at: Time.current)
  end
end
