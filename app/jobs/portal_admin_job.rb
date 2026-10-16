# B02a: every few minutes, the events of the portal go to the audit trail; every night, the people who no longer come are suspended.
class PortalAdminJob < ApplicationJob
  queue_as :default

  def perform(task = "mirror")
    task == "dormant" ? PortalAdmin::SuspendDormant.call : PortalAdmin::MirrorEvents.call
  end
end
