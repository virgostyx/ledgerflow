# Hourly (B03c): asks the timestamp authority for the tokens of the anchors that do not have one yet.
class Ledger::TimestampJob < ApplicationJob
  queue_as :default

  def perform = Ledger::Timestamping.retry_pending
end
