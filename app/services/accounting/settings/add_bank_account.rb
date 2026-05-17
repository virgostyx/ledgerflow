class Accounting::Settings::AddBankAccount
  extend LightService::Organizer

  def self.call(params:, user:)
    result = nil
    ApplicationRecord.transaction do
      result = with(params: params, user: user).reduce(
        Accounting::Settings::Actions::ValidateBankAccountParams,
        Accounting::Settings::Actions::BuildBankJournal,
        Accounting::Settings::Actions::PersistBankJournal,
        Accounting::Settings::Actions::PersistBankAccount
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    ctx = LightService::Context.make(params: params, user: user)
    ctx.fail!("Error: #{e.message}")
    ctx
  end
end
