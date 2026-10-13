# B01b: "Payments" in five steps - the invoices to pay (new), the composition (create, show), the checks (preflight, acknowledge), the approval (submit_for_approval, decide)
# and the file with what follows (export, download, confirm_loaded, cancel, confirm_cancellation) - and the history (index). Every action goes through a service that holds the
# rules; nothing here pays anything or writes an entry. IBANs are shown masked; the file, which holds them, goes to those who may export or confirm.
class Accounting::PaymentsController < ApplicationController
  before_action { require_feature!(:b01b) }
  before_action :set_batch, except: %i[index new create executed]
  before_action(only: %i[export download]) { require_recent_second_factor! } # the file holds the accounts paid: a second factor given a moment ago

  def index
    authorize Payments::Batch
    @batches = Payments::Batch.includes(:bank_account, :prepared_by).order(created_at: :desc).limit(200)
    @indicators = Payments::Indicators.call((Date.current - 90)..Date.current)
  end

  # "Paiements exécutés": the payments the bank debited, invoice by invoice, for the auditor (CSV, XLSX).
  def executed
    authorize Payments::Batch, :index?
    range = (date_param(params[:from]) || Date.current - 90)..(date_param(params[:to]) || Date.current)
    result = Payments::ExecutedPayments.call(range)
    name = "executed-payments-#{range.first.iso8601}-#{range.last.iso8601}"
    respond_to do |format|
      format.csv { send_data Reports::Exporters::Csv.call(result, columns: Payments::ExecutedPayments::COLUMNS), filename: "#{name}.csv", type: "text/csv" }
      format.xlsx { send_data Reports::Exporters::Xlsx.call(result, columns: Payments::ExecutedPayments::COLUMNS, title: "Executed payments"), filename: "#{name}.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }
    end
  end

  def new
    authorize Payments::Batch, :create?
    @execution_date = date_param(params[:execution_date]) || Payments::SettlementCalendar.next_open(Date.current + 1)
    @bank_accounts = Accounting::BankAccount.active.where(currency: "EUR")
    @profiles = Payments::BankProfile.order(:name)
    @rows = Payments::Eligibility.call(execution_date: @execution_date)
  end

  def create
    authorize Payments::Batch, :create?
    attrs = params.require(:payment).permit(:bank_account_id, :bank_profile_id, :requested_execution_date, :net_credit_notes, invoice_ids: [])
    result = Payments::ComposeBatch.call(bank_account: Accounting::BankAccount.find(attrs[:bank_account_id]), execution_date: date_param(attrs[:requested_execution_date]),
                                         selections: Array(attrs[:invoice_ids]).reject(&:blank?).map { |id| { invoice_id: id.to_i } }, user: current_user,
                                         net_credit_notes: attrs[:net_credit_notes] == "1", bank_profile: Payments::BankProfile.find_by(id: attrs[:bank_profile_id]))
    if result.success?
      redirect_to accounting_payment_path(result[:batch]), notice: t("payments.screens.composed")
    else
      @execution_date = date_param(attrs[:requested_execution_date]) || Date.current
      @bank_accounts = Accounting::BankAccount.active.where(currency: "EUR")
      @profiles = Payments::BankProfile.order(:name)
      @rows = Payments::Eligibility.call(execution_date: @execution_date)
      flash.now[:alert] = result.message
      render :new, status: :unprocessable_content
    end
  end

  def show
    authorize @batch
    @items = @batch.items.includes(:partner, :partner_bank_account, :journal_entry, item_invoices: :invoice).order(:id)
    @report = @batch.preflight_report.presence
    @balance = Payments::Balance.of(@batch.bank_account)
    @request = @batch.approval_request
    # the buttons are for who may decide; the one who prepared the batch is not offered them when the company keeps the tasks apart (Approvals::Decide refuses them anyway)
    @timeline = Payments::Timeline.for_batch(@batch)
    @waiting_items = @items.select(&:included?) if @batch.partially_rejected? || @items.any?(&:confirmed?)
    @drafts = @items.select { |item| item.confirmed? && item.journal_entry&.draft? }
    @can_decide = @request&.pending? && Approvals::Approvers.for(@request).key?(current_user.id) && !(@batch.entity.distinct_payment_authorizer? && @batch.prepared_by_id == current_user.id)
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

  def confirm_debit_by_hand
    authorize @batch, :confirm?
    result = Payments::ConfirmDebit.manual(batch: @batch, user: current_user, reason: params[:reason].to_s, date: date_param(params[:date]), bank_reference: params[:bank_reference].to_s)
    answer(result, t("payments.screens.debit_confirmed"))
  end

  def post_payments
    authorize @batch, :post_entries?
    answer(Payments::PostBatchPayments.call(batch: @batch, user: current_user), t("payments.screens.payments_validated"))
  end

  def reject_payments
    authorize @batch, :confirm?
    items = @batch.items.where(id: Array(params[:item_ids]))
    answer(Payments::RejectPayments.call(batch: @batch, items: items.to_a, user: current_user, reason: params[:reason].to_s), t("payments.screens.rejected"))
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
