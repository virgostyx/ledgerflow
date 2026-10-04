# F07: posting a reversal flags the entry it reverses and writes its audit row (reason included), whoever posts it: the reversal
# service, or a person validating a scheduled draft reversal. The lines of the two entries on a lettrable account cancel each other: they
# are lettered together (automatic, settling no invoice), so that neither shows as an open item in R04 and R05. A lettering that cannot be
# made is left for the lettering screen.
class Accounting::Actions::MarkReversedOriginal
  extend LightService::Action

  expects :entry

  executed do |ctx|
    next unless ctx.entry.reversal_of_id

    original = Accounting::JournalEntry.find(ctx.entry.reversal_of_id)
    next unless original.posted?

    original.reverse!
    Accounting::AuditLog.record!(auditable: original, action: "reverse_entry", payload: { reversal_id: ctx.entry.id }, reason: ctx.entry.reversal_reason.presence)
    letter_pairs(original, ctx.entry)
  end

  def self.letter_pairs(original, reversal)
    counterparts = reversal.lines.includes(:account).to_a
    original.lines.includes(:account).each do |line|
      next unless line.account.reconcilable && line.lettering_id.nil?

      mirror = counterparts.find { |c| c.lettering_id.nil? && c.account_id == line.account_id && c.partner_id == line.partner_id && c.debit == line.credit && c.credit == line.debit }
      next unless mirror

      counterparts.delete(mirror)
      Accounting::LetterLines.call(lines: [ line, mirror ], auto: true, settle: false)
    end
  end
end
