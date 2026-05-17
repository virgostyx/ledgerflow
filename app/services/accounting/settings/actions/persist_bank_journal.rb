class Accounting::Settings::Actions::PersistBankJournal
  extend LightService::Action

  expects :journal

  executed do |ctx|
    unless ctx.journal.save
      ctx.fail!(ctx.journal.errors.full_messages.first)
    end
  end
end
