class Accounting::Actions::CreateLettering
  extend LightService::Action

  expects  :lines
  promises :lettering

  executed do |ctx|
    first = ctx.lines.first
    cross = ctx.lines.map(&:partner_id).uniq.size > 1
    ctx.lettering = Accounting::Lettering.create!(
      account:     first.account,
      partner_id:  (first.partner_id unless cross),
      code:        Accounting::Lettering.next_code_for(first.account),
      lettered_on: Date.current,
      kind:        ctx[:kind] || "full",
      auto:        ctx[:auto] || false,
      reason:      (ctx[:reason] if cross),
      lettered_by: ctx[:user]
    )
    ids = ctx.lines.map(&:id)
    Accounting::JournalEntryLine.where(id: ids).update_all(lettering_id: ctx.lettering.id)
    Accounting::JournalEntryLine.resync_amount_residual!(ids)
    Accounting::LetteringEvent.record!(lines: ctx.lines, action: "letter", code: ctx.lettering.code, user: ctx[:user], auto: ctx[:auto] || false, reason: (ctx[:reason] if cross))
  end
end
