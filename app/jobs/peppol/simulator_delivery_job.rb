# What the Peppol simulator does once a document has been "sent": reports the delivery (or its failure) the way an
# Access Point webhook would, through the same Peppol::HandleEvent.
class Peppol::SimulatorDeliveryJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true # see Peppol::AccessPoint::Simulator: the message id is stored on commit

  def perform(message_id, outcome, error = nil)
    Peppol::HandleEvent.call(event: Peppol::Event.new(kind: outcome.to_sym, message_id: message_id, error: error))
  end
end
