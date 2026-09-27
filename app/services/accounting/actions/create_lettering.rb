class Accounting::Actions::CreateLettering
  extend LightService::Action

  expects  :lines
  promises :lettering

  executed do |ctx|
    first = ctx.lines.first
    ctx.lettering = Accounting::Lettering.create!(
      account:     first.account,
      partner_id:  first.partner_id,
      code:        Accounting::Lettering.next_code_for(first.account),
      lettered_on: Date.current
    )
    ids = ctx.lines.map(&:id)
    Accounting::JournalEntryLine.where(id: ids).update_all(lettering_id: ctx.lettering.id)
    Accounting::JournalEntryLine.resync_amount_residual!(ids)
  end
end
