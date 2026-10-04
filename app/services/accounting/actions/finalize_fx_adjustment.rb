# An exchange difference kept as a draft (`fx_realized_as_draft`, F11) joins its lettering when a person posts it: its trade line is added to the lettering,
# which then balances in EUR as well.
class Accounting::Actions::FinalizeFxAdjustment
  extend LightService::Action

  expects :entry

  executed do |ctx|
    entry = ctx.entry
    next unless entry.source_type == Accounting::JournalEntry::FX_SOURCE && entry.lettering_id

    lettering = Accounting::Lettering.find(entry.lettering_id)
    trade_line = entry.lines.find_by(account_id: lettering.account_id)
    next unless trade_line

    trade_line.update_columns(lettering_id: lettering.id)
    Accounting::JournalEntryLine.resync_amount_residual!([ trade_line.id ])
  end
end
