class Peppol::WebhooksController < ApplicationController
  skip_before_action :authenticate_user!
  skip_forgery_protection

  before_action :verify_hmac_signature!

  def receive
    payload = JSON.parse(request.body.read)
    event   = payload["event"]

    case event
    when "INVOICE_DELIVERED"
      handle_delivery(payload)
    when "INVOICE_RECEIVED"
      handle_incoming(payload)
    end

    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def verify_hmac_signature!
    signature = request.headers["X-Peppol-Signature"]
    raw_body  = request.body.read
    request.body.rewind

    return head :unauthorized if signature.blank?

    expected = OpenSSL::HMAC.hexdigest("SHA256", DIGITEAL_HMAC_SECRET, raw_body)
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  def handle_delivery(payload)
    peppol_id = payload["document_id"]
    status    = payload["status"]
    invoice   = Accounting::Invoice.find_by(peppol_id: peppol_id)
    return unless invoice

    peppol_status = map_peppol_status(status)
    invoice.update!(peppol_status: peppol_status)
  end

  def handle_incoming(payload)
    ubl_xml     = payload["ubl_xml"]
    fiscal_year = Accounting::FiscalYear.find_by(status: :open)
    return unless fiscal_year && ubl_xml.present?

    Peppol::ReceiveInvoice.call(xml: ubl_xml, fiscal_year: fiscal_year)
  end

  def map_peppol_status(status)
    case status&.upcase
    when "DELIVERED" then :delivered
    when "FAILED"    then :failed
    else :queued
    end
  end
end
