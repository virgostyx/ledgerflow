class Accounting::PaymentBatchesController < ApplicationController
  before_action :set_payment_batch, only: [ :show, :destroy, :generate, :execute, :download ]

  def index
    @payment_batches = policy_scope(Accounting::PaymentBatch).order(created_at: :desc)
  end

  def new
    @payment_batch     = Accounting::PaymentBatch.new
    @bank_accounts     = Accounting::BankAccount.active
    @eligible_invoices = eligible_invoices
    authorize @payment_batch
  end

  def create
    @payment_batch = Accounting::PaymentBatch.new
    authorize @payment_batch

    bank_account = Accounting::BankAccount.find_by(id: payment_batch_params[:bank_account_id])
    result = Payments::CreateDraftBatch.call(
      invoice_ids: Array(payment_batch_params[:invoice_ids]).reject(&:blank?),
      bank_account: bank_account,
      requested_execution_date: payment_batch_params[:requested_execution_date]
    )

    if result.success?
      redirect_to accounting_payment_batch_path(result.payment_batch),
                  notice: t("payments.payment_batches.created")
    else
      @bank_accounts     = Accounting::BankAccount.active
      @eligible_invoices = eligible_invoices
      flash.now[:alert] = result.message
      render :new, status: :unprocessable_content
    end
  end

  def show
    authorize @payment_batch
  end

  def destroy
    authorize @payment_batch

    if @payment_batch.destroyable?
      @payment_batch.destroy!
      redirect_to accounting_payment_batches_path, notice: t("payments.payment_batches.deleted")
    else
      redirect_to accounting_payment_batch_path(@payment_batch),
                  alert: t("payments.errors.not_destroyable")
    end
  end

  def generate
    authorize @payment_batch, :generate?

    result = Payments::GenerateSepaFile.call(payment_batch: @payment_batch)

    if result.success?
      redirect_to accounting_payment_batch_path(@payment_batch), notice: t("payments.payment_batches.generated")
    else
      redirect_to accounting_payment_batch_path(@payment_batch), alert: result.message
    end
  end

  def execute
    authorize @payment_batch, :execute?

    result = Payments::ExecutePaymentBatch.call(payment_batch: @payment_batch)

    if result.success?
      redirect_to accounting_payment_batch_path(@payment_batch), notice: t("payments.payment_batches.executed")
    else
      redirect_to accounting_payment_batch_path(@payment_batch), alert: result.message
    end
  end

  def download
    authorize @payment_batch, :download?

    send_data @payment_batch.sepa_xml,
              filename: "sepa-#{@payment_batch.message_id}.xml",
              type: "application/xml"
  end

  private

  def set_payment_batch
    @payment_batch = Accounting::PaymentBatch.find(params[:id])
  end

  def eligible_invoices
    excluded_ids = Accounting::PaymentBatchLine.active.select(:invoice_id)
    Accounting::Invoice.supplier.posted.where.not(id: excluded_ids).order(:due_date)
  end

  def payment_batch_params
    params.require(:accounting_payment_batch).permit(:bank_account_id, :requested_execution_date, invoice_ids: [])
  end
end
