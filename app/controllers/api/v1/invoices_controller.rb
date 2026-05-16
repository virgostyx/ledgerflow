class Api::V1::InvoicesController < Api::V1::BaseController
  def index
    invoices = Accounting::Invoice.all
    invoices = invoices.where(status: params[:status]) if params[:status].present?
    invoices = invoices.order(invoice_date: :desc)
    render json: invoices.map { |i| serialize_invoice(i) }
  end

  def show
    invoice = Accounting::Invoice.find(params[:id])
    render json: serialize_invoice(invoice)
  end

  private

  def serialize_invoice(invoice)
    {
      id:             invoice.id,
      invoice_number: invoice.invoice_number,
      status:         invoice.status,
      invoice_date:   invoice.invoice_date,
      total_incl_vat: invoice.total_incl_vat,
      partner_id:     invoice.partner_id
    }
  end
end
