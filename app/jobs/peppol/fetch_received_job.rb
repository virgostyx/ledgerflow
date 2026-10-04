# F06 step 6: fetches the XML of a received document (Peppol::FetchReceived) and retries after a technical error, 1 minute, 5 minutes, then 30
# minutes; after that the message waits for review ("Work on it again" fetches it again), it is never lost.
class Peppol::FetchReceivedJob < ApplicationJob
  queue_as :default

  WAITS = [ 1.minute, 5.minutes, 30.minutes ].freeze

  def perform(message_id, entity_id, attempt = 1)
    ActsAsTenant.with_tenant(Entity.find(entity_id)) do
      message = Accounting::PeppolMessage.inbound.find_by(id: message_id, status: :received) or next
      begin
        Peppol::FetchReceived.call(message: message)
      rescue Peppol::AccessPoint::TemporaryError => e
        again(message, entity_id, attempt, e.message)
      end
    end
  end

  private

  def again(message, entity_id, attempt, reason)
    if attempt > WAITS.size
      return message.update!(status: :needs_review, problems: [ "The document could not be fetched from the Access Point after #{attempt} attempts: #{reason}" ])
    end

    message.update!(problems: [ "To be fetched again: #{reason}" ])
    self.class.set(wait: WAITS.fetch(attempt - 1)).perform_later(message.id, entity_id, attempt + 1)
  end
end
