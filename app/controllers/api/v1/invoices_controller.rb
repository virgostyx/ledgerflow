# Invoices seen from third-party applications, addressed by their own reference (external_ref).
# Writes go through Accounting::ExternalInvoice (docs/dev/api/inbound-api.md).
class Api::V1::InvoicesController < Api::V1::BaseController
  self.action_scopes = { index: "invoices:read", show: "invoices:read", update: "invoices:write", destroy: "invoices:write" }

  LINE_FIELDS = %i[account_code description quantity unit_price vat_rate].freeze
  STATUS_CODES = { created: :created, ok: :ok, unprocessable: :unprocessable_content, conflict: :conflict, not_found: :not_found }.freeze

  def index
    invoices = Accounting::Invoice.all
    invoices = invoices.where(status: params[:status]) if params[:status].present?
    invoices = invoices.order(invoice_date: :desc)
    render json: invoices.map { |i| serialize_invoice(i) }
  end

  def show
    revisions = Accounting::Invoice.external.where(external_ref: params[:external_ref]).order(:revision)
    current   = revisions.last
    return render(json: { error: "Not found" }, status: :not_found) unless current

    render json: serialize_detail(current).merge(revisions: revisions.map { |r| serialize_invoice(r).slice(:revision, :status, :invoice_number) })
  end

  def update
    respond Accounting::ExternalInvoice.upsert(invoice_payload)
  end

  def destroy
    respond Accounting::ExternalInvoice.cancel(external_ref: params[:external_ref], reason: params[:reason])
  end

  private

  def invoice_payload
    params.permit(:partner_external_ref, :post, :project_name, :budget_line, :document_type, :credited_invoice_external_ref, :invoice_type, :invoice_date, :due_date, :currency, :exchange_rate,
                  :vat_treatment, :description, :notes, :project_id, lines: LINE_FIELDS)
          .to_h.merge(external_ref: params[:external_ref])
  end

  def respond(result)
    body = result.invoice ? serialize_detail(result.invoice) : { errors: result.errors }
    render json: body, status: STATUS_CODES.fetch(result.status)
  end

  # Single-document responses also name the credited invoice (one lookup; not used in lists).
  def serialize_detail(invoice)
    serialize_invoice(invoice).merge(credited_invoice_external_ref: invoice.credited_invoice&.external_ref,
                                     project_name: invoice.external_project_name, budget_line: invoice.external_budget_line)
  end

  def serialize_invoice(invoice)
    {
      id:             invoice.id,
      external_ref:   invoice.external_ref,
      revision:       invoice.revision,
      document_type:  invoice.document_type,
      invoice_number: invoice.invoice_number,
      status:         invoice.status,
      invoice_date:   invoice.invoice_date,
      total_incl_vat: invoice.total_incl_vat,
      partner_id:     invoice.partner_id
    }
  end
end
