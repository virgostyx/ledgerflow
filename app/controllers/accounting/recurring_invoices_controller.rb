class Accounting::RecurringInvoicesController < ApplicationController
  before_action :set_recurring_invoice, only: %i[edit update destroy]

  def index
    authorize Accounting::RecurringInvoice
    @recurring_invoices = policy_scope(Accounting::RecurringInvoice).includes(source_invoice: :partner).order(:id)
  end

  def new
    authorize Accounting::RecurringInvoice

    source = Accounting::Invoice.find_by(id: params[:invoice_id])
    unless source&.invoice? && source.issued?
      return redirect_to accounting_recurring_invoices_path, alert: t("accounting.recurring_invoices.errors.not_a_source")
    end

    @recurring_invoice = Accounting::RecurringInvoice.new(source_invoice: source, frequency: :monthly, start_on: source.invoice_date >> 1)
  end

  def create
    @recurring_invoice = Accounting::RecurringInvoice.new(create_params)
    authorize @recurring_invoice

    if @recurring_invoice.save
      redirect_to accounting_recurring_invoices_path, notice: t("accounting.recurring_invoices.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @recurring_invoice
  end

  def update
    authorize @recurring_invoice

    attrs    = update_params
    resuming = !@recurring_invoice.active? && ActiveModel::Type::Boolean.new.cast(attrs[:active])
    if resuming
      @recurring_invoice.resume!
      attrs = attrs.except(:active)
    end

    if @recurring_invoice.update(attrs)
      redirect_to accounting_recurring_invoices_path, notice: t("accounting.recurring_invoices.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @recurring_invoice
    @recurring_invoice.destroy!
    redirect_to accounting_recurring_invoices_path, notice: t("accounting.recurring_invoices.deleted")
  end

  private

  def set_recurring_invoice
    @recurring_invoice = Accounting::RecurringInvoice.find(params[:id])
  end

  def create_params
    params.require(:accounting_recurring_invoice).permit(:source_invoice_id, :frequency, :start_on, :end_on)
  end

  # Once created the schedule itself is fixed (changing it would move the next date): make a new one instead.
  def update_params
    params.require(:accounting_recurring_invoice).permit(:end_on, :active)
  end
end
