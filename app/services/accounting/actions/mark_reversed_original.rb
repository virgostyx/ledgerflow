# F07: posting a reversal flags the entry it reverses and writes its audit row (reason included), whoever posts it: the reversal
# service, or a person validating a scheduled draft reversal.
class Accounting::Actions::MarkReversedOriginal
  extend LightService::Action

  expects :entry

  executed do |ctx|
    next unless ctx.entry.reversal_of_id

    original = Accounting::JournalEntry.find(ctx.entry.reversal_of_id)
    next unless original.posted?

    original.reverse!
    Accounting::AuditLog.record!(auditable: original, action: "reverse_entry", payload: { reversal_id: ctx.entry.id }, reason: ctx.entry.reversal_reason.presence)
  end
end
