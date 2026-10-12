# B01b: "Payments" in five steps - the invoices to pay (new), the composition (create, show), the checks (preflight, acknowledge), the approval (submit_for_approval, decide)
# and the file with what follows (export, download, confirm_loaded, cancel, confirm_cancellation) - and the history (index). Every action goes through a service that holds the
# rules; nothing here pays anything or writes an entry. IBANs are shown masked; the file, which holds them, goes to those who may export or confirm.
class Accounting::PaymentsController < ApplicationController
  before_action { require_feature!(:b01b) }
  before_action :set_batch, except: %i[index new create]
  before_action(only: :export) { require_recent_second_factor! }

  def index
    authorize Payments::Batch
    @batches = Payments::Batch.includes(:bank_account, :prepared_by).order(created_at: :desc).limit(200)
  end

  def new
    authorize Payments::Batch, :create?
    @execution_date = date_param(params[:execution_date]) || Payments::SettlementCalendar.next_open(Date.current + 1)
    @bank_accounts = Accounting::BankAccount.active.where(currency: "EUR")
    @rows = Payments::Eligibility.call(execution_date: @execution_date)
  end

  def create
    authorize Payments::Batch, :create?
    attrs = params.require(:payment).permit(:bank_account_id, :requested_execution_date, :net_credit_notes, invoice_ids: [])
    result = Payments::ComposeBatch.call(bank_account: Accounting::BankAccount.find(attrs[:bank_account_id]), execution_date: date_param(attrs[:requested_execution_date]),
                                         selections: Array(attrs[:invoice_ids]).reject(&:blank?).map { |id| { invoice_id: id.to_i } }, user: current_user,
                                         net_credit_notes: attrs[:net_credit_notes] == "1")
    if result.success?
      redirect_to accounting_payment_path(result[:batch]), notice: t("payments.screens.composed")
    else
      @execution_date = date_param(attrs[:requested_execution_date]) || Date.current
      @bank_accounts = Accounting::BankAccount.active.where(currency: "EUR")
      @rows = Payments::Eligibility.call(execution_date: @execution_date)
      flash.now[:alert] = result.message
      render :new, status: :unprocessable_content
    end
  end

  def show
    authorize @batch
    @items = @batch.items.includes(:partner, :partner_bank_account, item_invoices: :invoice).order(:id)
    @report = @batch.preflight_report.presence
    @balance = Payments::Balance.of(@batch.bank_account)
    @request = @batch.approval_request
    @can_decide = @request&.pending? && Approvals::Approvers.for(@request).key?(current_user.id)
  end

  def preflight
    authorize @batch, :show?
    Payments::Preflight.call(@batch)
    redirect_to accounting_payment_path(@batch), notice: t("payments.screens.checked")
  end

  def acknowledge
    authorize @batch, :show?
    result = Payments::AcknowledgeWarning.call(batch: @batch, key: params[:key].to_s, reason: params[:reason].to_s.strip, user: current_user)
    answer(result, t("payments.screens.acknowledged"))
  end

  def submit_for_approval
    authorize @batch, :create?
    answer(Payments::SubmitBatch.call(batch: @batch, user: current_user), t("payments.screens.submitted_for_approval"))
  end

  def decide
    authorize @batch, :approve?
    request = @batch.approval_request or return redirect_to(accounting_payment_path(@batch), alert: t("approvals.errors.not_pending"))
    result = Approvals::Decide.call(request: request, user: current_user, decision: params[:decision].to_s, comment: params[:comment].presence, content_fingerprint: params[:content_fingerprint].to_s,
                                    recent_second_factor: recent_second_factor?, channel: :web)
    return ask_for_second_factor!(back_to: accounting_payment_path(@batch)) if result[:code] == :step_up_required

    answer(result, t("approvals.decided.#{params[:decision]}", default: t("payments.screens.decided")))
  end

  def export
    authorize @batch, :export?
    answer(Payments::ExportBatch.call(batch: @batch, user: current_user, recent_second_factor: recent_second_factor?), t("payments.screens.exported"))
  end

  def download
    authorize @batch, :export?
    return redirect_to(accounting_payment_path(@batch), alert: t("payments.screens.no_file")) unless @batch.document
    Accounting::AuditLog.record!(auditable: @batch, action: "payment_file_downloaded", user: current_user, payload: { sha256: @batch.file_sha256 })
    send_data @batch.document.file.download, filename: "#{@batch.reference}.xml", type: "application/xml"
  end

  def confirm_loaded
    authorize @batch, :confirm?
    answer(Payments::ConfirmSubmission.call(batch: @batch, user: current_user), t("payments.screens.loaded"))
  end

  def cancel
    authorize @batch, :show?
    answer(Payments::CancelBatch.call(batch: @batch, user: current_user, reason: params[:reason].to_s), t("payments.screens.cancelled"))
  end

  def confirm_cancellation
    authorize @batch, :confirm?
    answer(Payments::ConfirmCancellation.call(batch: @batch, user: current_user), t("payments.screens.cancellation_done"))
  end

  private

  def set_batch = @batch = Payments::Batch.find(params[:id])

  def answer(result, notice)
    if result.success?
      redirect_to accounting_payment_path(@batch), notice: notice
    else
      redirect_to accounting_payment_path(@batch), alert: result.message
    end
  end

  def date_param(value)
    Date.iso8601(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end
end
