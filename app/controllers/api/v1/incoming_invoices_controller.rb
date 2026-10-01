# Peppol invoices received in LedgerFlow, as seen by the third party that takes them over (BudgetFlow): their documents, and the
# claim that makes the draft its own (docs/dev/api/inbound-api.md). It learns of them through the `received` event.
class Api::V1::IncomingInvoicesController < Api::V1::BaseController
  self.action_scopes = { claim: "invoices:write", document: "invoices:read" }
  STATUS_CODES = { ok: :ok, unprocessable: :unprocessable_content, conflict: :conflict }.freeze

  before_action :set_invoice

  def claim
    result = Accounting::ClaimIncomingInvoice.call(invoice: @invoice, external_ref: params[:external_ref])
    body = result.invoice ? summary(result.invoice) : { errors: result.errors }
    render json: body, status: STATUS_CODES.fetch(result.status)
  end

  def document
    attachment = { "xml" => @invoice.ubl_document, "pdf" => @invoice.pdf_document }[params[:kind]]
    return render(json: { error: "Not found" }, status: :not_found) unless attachment&.attached?

    send_data attachment.download, filename: attachment.filename.to_s, type: attachment.content_type,
                                   disposition: params[:kind] == "pdf" ? "inline" : "attachment"
  end

  private

  def set_invoice
    @invoice = Accounting::Invoice.peppol_received.find_by(id: params[:id])
    render json: { error: "Not found" }, status: :not_found unless @invoice
  end

  def summary(invoice)
    { id: invoice.id, external_ref: invoice.external_ref, status: invoice.status, supplier_reference: invoice.supplier_reference,
      order_reference: invoice.order_reference, buyer_reference: invoice.buyer_reference }
  end
end
