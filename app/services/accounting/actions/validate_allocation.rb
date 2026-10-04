class Accounting::Actions::ValidateAllocation
  extend LightService::Action

  expects :lines

  executed do |ctx|
    lines = ctx.lines
    error = if lines.size < 2                                              then "Select at least two lines"
    elsif lines.none? { |l| l.debit > 0 } || lines.none? { |l| l.credit > 0 } then "Select at least one debit and one credit line"
    elsif lines.any? { |l| !l.journal_entry.in_ledger? }                   then "Only lines of posted entries can be allocated"
    elsif lines.any?(&:lettering_id)                                       then "A line is already lettered"
    elsif Accounting::JournalEntryLine.carried_forward.where(id: lines.map(&:id)).exists? then "A line was carried into the next fiscal year: allocate the carried line instead."
    elsif lines.map(&:account_id).uniq.size > 1                            then "Lines must be on the same account"
    elsif lines.map(&:partner_id).uniq.size > 1                            then "Lines must have the same partner"
    elsif lines.any? { |l| l.open_amount <= 0 }                            then "A line has nothing left to allocate"
    elsif lines.any? { |l| l.currency != "EUR" && !l.journal_entry.fx_adjustment? } then "Lines in a foreign currency cannot be allocated by hand: a partial payment is booked through the bank reconciliation, which computes the exchange difference."
    end
    ctx.fail!(error) if error
  end
end
