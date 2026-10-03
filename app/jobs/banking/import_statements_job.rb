# The background import of a big statement file (F02). The batch was created when the file arrived (processing); the job imports
# the file it kept, into that batch, and lets go of it. The guarantees are the import's own: whole or nothing, never twice.
class Banking::ImportStatementsJob < ApplicationJob
  queue_as :default

  def perform(batch_id, entity_id)
    ActsAsTenant.with_tenant(Entity.find(entity_id)) do
      batch = Accounting::ImportBatch.find(batch_id)
      next unless batch.result == "processing" && batch.queued_file.attached?

      begin
        Banking::ImportStatements.call(bytes: batch.queued_file.download, user: batch.user, source_name: batch.source_name, batch: batch)
      rescue StandardError => e
        # whatever went wrong, the batch must not stay "processing" for ever
        batch.update!(result: "rejected", errors_list: [ { text: I18n.t("banking.import.failed", detail: e.message.truncate(200)) } ])
      ensure
        batch.queued_file.purge if batch.queued_file.attached?
      end
    end
  end
end
