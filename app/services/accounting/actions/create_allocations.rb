# Matches open debit and credit amounts oldest due date first until one side runs out.
class Accounting::Actions::CreateAllocations
  extend LightService::Action

  expects :lines

  executed do |ctx|
    queue = ->(lines) { lines.sort_by { |l| [ l.invoice&.due_date || l.journal_entry.entry_date, l.id ] }.map { |l| [ l, l.open_amount ] } }
    debits  = queue.(ctx.lines.select { |l| l.debit > 0 })
    credits = queue.(ctx.lines.select { |l| l.credit > 0 })

    until debits.empty? || credits.empty?
      amount = [ debits.first.last, credits.first.last ].min
      Accounting::LineAllocation.create!(debit_line: debits.first.first, credit_line: credits.first.first,
                                         amount: amount, allocated_on: Date.current)
      debits.first[1]  -= amount
      credits.first[1] -= amount
      debits.shift  if debits.first&.last&.zero?
      credits.shift if credits.first&.last&.zero?
    end
  end
end
