# Payment events of API-managed invoices, polled by the third party with a cursor (`after` = last event id it
# processed). Events are append-only and only shown once older than InvoiceEvent::SETTLE_DELAY.
class Api::V1::InvoiceEventsController < Api::V1::BaseController
  self.action_scopes = { index: "invoices:read" }

  DEFAULT_LIMIT = 100
  MAX_LIMIT     = 500

  def index
    after  = params[:after].to_i
    limit  = params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_LIMIT) : DEFAULT_LIMIT
    events = Accounting::InvoiceEvent.visible.where("id > ?", after).order(:id).limit(limit).to_a

    render json: { events: events.map { |e| serialize(e) }, next_cursor: events.last&.id || after }
  end

  private

  def serialize(event)
    event.payload.merge("id" => event.id, "type" => event.event_type, "occurred_at" => event.occurred_at.iso8601)
  end
end
