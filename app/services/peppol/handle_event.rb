# Applies an Access Point event (Peppol::Event) to the application, whichever provider it comes from: a real webhook or
# the simulator. A webhook or a job has no tenant: the invoice, or the entity a document is addressed to, is found across
# entities, then worked on in its own tenant.
# What it cannot place is ignored, not failed (an AP may tell us about documents we know nothing about).
class Peppol::HandleEvent
  DEFAULT_MESSAGES = { delivered: "Delivered to the receiver", failed: "The Access Point reported a delivery failure" }.freeze

  def self.call(event:)
    ctx = LightService::Context.make(event: event, invoice: nil, ignored: false)
    kind = event.kind.to_s.to_sym

    if kind == :received
      receive(ctx, event)
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

    ActsAsTenant.with_tenant(invoice.entity) { record(invoice, kind, event.error.presence || DEFAULT_MESSAGES.fetch(kind)) }
    ctx[:invoice] = invoice
  end

  # A document addressed to one of our entities becomes a draft supplier invoice in its open fiscal year.
  def self.receive(ctx, event)
    entity = event.receiver.present? && ActsAsTenant.without_tenant { Entity.find_by(peppol_participant_id: event.receiver) }
    return ctx[:ignored] = true unless entity

    ActsAsTenant.with_tenant(entity) do
      fiscal_year = Accounting::FiscalYear.current
      next ctx.fail!("#{entity.name} has no open fiscal year to book the document received") unless fiscal_year

      result = Peppol::ReceiveInvoice.call(xml: event.xml.to_s, fiscal_year: fiscal_year)
      result.failure? ? ctx.fail!(result.message) : ctx[:invoice] = result[:invoice]
    end
  end

  # Idempotent: an Access Point may send the same event twice.
  def self.record(invoice, kind, message)
    return if invoice.peppol_status == kind.to_s

    ApplicationRecord.transaction do
      invoice.update!(peppol_status: kind)
      invoice.peppol_events.create!(kind: kind, message: message)
    end
  end

  private_class_method :deliver, :receive, :record
end
