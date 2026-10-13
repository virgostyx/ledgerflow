# Daily (B01c): the batches that wait too long for their debit, or whose payments wait too long to be validated.
class Payments::CheckDelaysJob < ApplicationJob
  queue_as :default

  def perform = Payments::CheckDelays.call
end
