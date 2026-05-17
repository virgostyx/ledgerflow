class Accounting::Settings::Actions::BuildBankJournal
  extend LightService::Action

  expects :params, :counterpart_account

  executed do |ctx|
    p = ctx.params
    journal = Accounting::Journal.new(
      code:               p[:journal_code].upcase,
      label_fr:           p[:label_fr],
      journal_type:       :bank,
      sequence_prefix:    p[:journal_code].upcase,
      default_account:    ctx.counterpart_account,
      current_sequence:   0,
      active:             true
    )

    unless journal.valid?
      ctx.fail!(journal.errors.full_messages.first)
      next ctx
    end

    ctx[:journal] = journal
  end
end
