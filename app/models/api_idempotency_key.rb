# F13c: the answer given to a POST, kept under the `Idempotency-Key` of the caller so that sending it again gives the same answer and creates nothing
# more. While the first request still runs the answer is empty: a second one meets a conflict instead of a second creation.
class ApiIdempotencyKey < ApplicationRecord
  KEEP_FOR = 24.hours

  acts_as_tenant :entity
  belongs_to :api_client

  scope :stale, -> { where("created_at < ?", KEEP_FOR.ago) }

  def finished? = response_status.present?
end
