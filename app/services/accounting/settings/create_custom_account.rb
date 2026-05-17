class Accounting::Settings::CreateCustomAccount
  extend LightService::Organizer

  def self.call(params:, user:)
    result = nil
    ApplicationRecord.transaction do
      result = with(params: params, user: user).reduce(
        Accounting::Settings::Actions::ValidateCustomAccountParams,
        Accounting::Settings::Actions::PersistCustomAccount
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
