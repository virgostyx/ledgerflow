# F13a: the import of a large file, run in the background; the batch shows its progress.
class Imports::RunJob < ApplicationJob
  queue_as :default

  def perform(batch_id, user_id)
    batch = Accounting::ImportBatch.unscoped.find(batch_id)
    ActsAsTenant.with_tenant(batch.entity) { Imports::Run.call(batch: batch, user: User.find_by(id: user_id)) }
  end
end
