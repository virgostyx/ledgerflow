# F13c: an idempotency key is kept a day (long enough for a caller to retry); then it is forgotten.
class Api::PurgeIdempotencyKeysJob < ApplicationJob
  queue_as :default

  def perform = ApiIdempotencyKey.unscoped.stale.delete_all
end
