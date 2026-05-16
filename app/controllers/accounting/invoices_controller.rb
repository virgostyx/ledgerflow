class Accounting::InvoicesController < ApplicationController
  before_action :set_invoice, only: [ :show, :edit, :update, :destroy, :validate_invoice, :send_peppol ]

  def index
    @invoices = policy_scope(Accounting::Invoice).order(invoice_date: :desc)
  end

  def show
    authorize @invoice
  end

  def new
    @invoice = Accounting::Invoice.new
    authorize @invoice
  end

  def create
    @invoice = Accounting::Invoice.new(invoice_params)
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

    if @invoice.draft?
      @invoice.destroy!
      redirect_to accounting_invoices_path, notice: t("accounting.invoices.deleted")
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

  def invoice_params
    params.require(:accounting_invoice).permit(
      :invoice_type, :invoice_date, :due_date, :partner_id,
      :fiscal_year_id, :currency, :description, :notes, :external_ref
    )
  end
end
