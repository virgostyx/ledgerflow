# F13b: builds the full backup of an entity in the background, and says when it could not.
class Exports::BackupJob < ApplicationJob
  queue_as :default

  def perform(data_export_id)
    export = DataExport.unscoped.find(data_export_id)
    Exports::Backup.call(data_export: export)
  rescue StandardError => e
    export&.update!(status: "failed", error: e.message.first(255))
  end
end
