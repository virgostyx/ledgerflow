class Accounting::Actions::AssignSequenceNumber
  extend LightService::Action

  expects  :entry
  promises :entry

  executed do |ctx|
    entry = ctx.entry
    entry.reference = entry.journal.next_sequence_number(year: entry.entry_date.year)
    entry.save!
    ctx.entry = entry
  end
end
