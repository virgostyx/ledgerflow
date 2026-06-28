class Accounting::InvoicesController < ApplicationController
  before_action :set_invoice, only: [ :show, :edit, :update, :destroy, :validate_invoice, :send_peppol ]
  before_action :set_invoice_type_context, only: [ :index, :new, :create ]

  def index
    @invoices = policy_scope(Accounting::Invoice)
                  .where(invoice_type: @invoice_type)
                  .order(invoice_date: :desc)
  end

  def show
    authorize @invoice
  end

  def new
    @invoice = Accounting::Invoice.new(invoice_type: @invoice_type)
    authorize @invoice
  end

  def create
    @invoice = Accounting::Invoice.new(invoice_params.merge(invoice_type: @invoice_type))
    authorize @invoice

    if @invoice.save
      redirect_to accounting_invoice_path(@invoice), notice: t("accounting.invoices.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @invoice
  end

  def update
    authorize @invoice

    if @invoice.update(invoice_params)
      redirect_to accounting_invoice_path(@invoice), notice: t("accounting.invoices.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @invoice

    invoice_type = @invoice.invoice_type
    if @invoice.draft?
      @invoice.destroy!
      redirect_to list_path_for(invoice_type), notice: t("accounting.invoices.deleted")
    else
      head :unprocessable_content
    end
  end

  def validate_invoice
    authorize @invoice, :post?

    result = Accounting::PostInvoice.call(invoice: @invoice)

    if result.success?
      redirect_to accounting_invoice_path(@invoice), notice: t("accounting.invoices.posted")
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  def send_peppol
    authorize @invoice, :send_peppol?

    result = Peppol::SendInvoice.call(invoice: @invoice)

    if result.success?
      redirect_to accounting_invoice_path(@invoice), notice: t("peppol.invoices.sent")
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  private

  def set_invoice
    @invoice = Accounting::Invoice.find(params[:id])
  end

  def set_invoice_type_context
    @invoice_type = params[:invoice_type].presence
  end

  def list_path_for(invoice_type)
    invoice_type.to_s == "customer" ? accounting_sales_path : accounting_purchases_path
  end

  def invoice_params
    params.require(:accounting_invoice).permit(
      :invoice_date, :due_date, :partner_id,
      :fiscal_year_id, :currency, :description, :notes, :external_ref
    )
  end
end
