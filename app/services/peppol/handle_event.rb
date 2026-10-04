# Applies an Access Point event (Peppol::Event) to the application, whichever provider it comes from: a real webhook or
# the simulator. A webhook or a job has no tenant: the invoice, or the entity a document is addressed to, is found across
# entities, then worked on in its own tenant.
# What it cannot place is ignored, not failed (an AP may tell us about documents we know nothing about).
class Peppol::HandleEvent
  DEFAULT_MESSAGES = { delivered: "Delivered to the receiver", failed: "The Access Point reported a delivery failure" }.freeze

  # `entity`: given when the call is already known to be for it (the token of its webhook, a signature checked): a received document announced
  # by an Access Point that does not name the receiver (B2Brouter) is then recorded in it.
  def self.call(event:, entity: nil)
    ctx = LightService::Context.make(event: event, invoice: nil, ignored: false)
    kind = event.kind.to_s.to_sym

    if kind == :received
      receive(ctx, event, entity)
    elsif DEFAULT_MESSAGES.key?(kind)
      deliver(ctx, event, kind)
    else
      ctx[:ignored] = true
    end
    ctx
  end

  def self.deliver(ctx, event, kind)
    invoice = event.message_id.present? && ActsAsTenant.without_tenant { Accounting::Invoice.find_by(peppol_id: event.message_id) }
    return ctx[:ignored] = true unless invoice

    ActsAsTenant.with_tenant(invoice.entity) { record(invoice, kind, event.error.presence || DEFAULT_MESSAGES.fetch(kind), event.raw) }
    ctx[:invoice] = invoice
  end

  # A document addressed to one of our entities is recorded first, then worked on (Peppol::ReceiveMessage): it is never lost, and a
  # document that cannot be worked on waits for a person. An exception here (the database is down) reaches the webhook, which answers 500
  # so that the Access Point sends the document again.
  def self.receive(ctx, event, entity = nil)
    entity ||= event.receiver.present? && ActsAsTenant.without_tenant { Entity.find_by(peppol_participant_id: event.receiver) }
    unless entity
      Rails.logger.warn("[Peppol] document received for #{event.receiver.presence || 'no receiver'}: no entity has that Peppol identifier, it is ignored")
      return ctx[:ignored] = true
    end

    ActsAsTenant.with_tenant(entity) do
      result = Peppol::ReceiveMessage.call(event: event)
      ctx[:message] = result[:message]
      ctx[:duplicate] = result[:duplicate]
      ctx[:invoice] = result[:invoice]
    end
  end

  # Idempotent: an Access Point may send the same event twice.
  def self.record(invoice, kind, message, raw = nil)
    return if invoice.peppol_status == kind.to_s

    ApplicationRecord.transaction do
      invoice.update!(peppol_status: kind)
      invoice.peppol_events.create!(kind: kind, message: message)
      Accounting::PeppolMessage.outbound.find_by(message_id: invoice.peppol_id)&.update!(status: kind, problems: (kind == :failed ? [ message ] : []), ack: raw.presence)
    end
  end

  private_class_method :deliver, :receive, :record
end
