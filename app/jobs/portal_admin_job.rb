# B02a: every few minutes, the events of the portal go to the audit trail; every night, the people who no longer come are suspended.
class PortalAdminJob < ApplicationJob
  queue_as :default

  def perform(task = "mirror")
    case task
    when "dormant" then PortalAdmin::SuspendDormant.call
    when "digest" then PortalAdmin::DailyDigest.call
    else PortalAdmin::MirrorEvents.call
    end
  end
end
