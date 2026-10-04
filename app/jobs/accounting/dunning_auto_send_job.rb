# Daily (F09): for an entity whose owner turned on `auto_send_level_1`, the first level is prepared and sent by itself, by e-mail only. Levels 2 and 3
# and letters are never sent without a person: they are not even prepared here. Nobody validates this run, so it is marked automatic.
class Accounting::DunningAutoSendJob < ApplicationJob
  queue_as :default

  def perform
    Entity.find_each { |entity| ActsAsTenant.with_tenant(entity) { send_level_1(entity) } }
  end

  private

  def send_level_1(entity)
    return unless entity.feature?(:f09) && Accounting::DunningPolicy.for(entity).auto_send_level_1

    run = Accounting::PrepareDunningRun.call(user: nil, only_level: 1, only_channel: "email", auto: true)[:run]
    Accounting::SendDunningRun.call(run: run, user: nil) if run
  end
end
