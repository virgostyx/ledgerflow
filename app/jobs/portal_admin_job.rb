# B02a: every few minutes, the events of the portal go to the audit trail (B02b: and what was sent is taken out of quarantine); every night, the people who no longer come are suspended.
class PortalAdminJob < ApplicationJob
  queue_as :default

  def perform(task = "mirror")
    case task
    when "snapshots"
      Entity.find_each { |entity| PortalAdmin::GenerateSnapshot.call(entity: entity) if entity.feature?(:b02a) && entity.feature?(:b02c) }
      PortalAdmin::DashboardAlerts.call
    when "dormant" then PortalAdmin::SuspendDormant.call
    when "digest" then PortalAdmin::DailyDigest.call
    when "uploads"
      PortalAdmin::ReceiveUploads.call
      PortalAdmin::SyncUploadProgress.call
      PortalAdmin::SyncDocumentRequests.call
      PortalAdmin::SyncAnswers.call
      PortalAdmin::SealApprovals.call
      PortalAdmin::ApprovalAlerts.call
    when "reminders"
      PortalAdmin::RemindDocumentRequests.call
      PortalAdmin::RemindQuestions.call
    else PortalAdmin::MirrorEvents.call
    end
  end
end
