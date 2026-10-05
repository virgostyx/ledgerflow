# F10: the closing assistant. The years to close, a run with its 18 steps read as they stand, the batch validation of the closing entries, the approval, the
# closing file, and the reopening.
class Accounting::ClosingRunsController < ApplicationController
  before_action { require_feature!(:f10) }
  before_action :set_run, only: %i[show validate_entries approve appropriate reopen bundle]

  def index
    authorize Accounting::ClosingRun
    @years = Accounting::FiscalYear.where.not(status: :closed).order(:year)
    @runs = Accounting::ClosingRun.includes(:fiscal_year, :opened_by).order(id: :desc)
  end

  def create
    authorize Accounting::ClosingRun
    year = Accounting::FiscalYear.find(params[:fiscal_year_id])
    result = Closing::OpenRun.call(fiscal_year: year, user: current_user)
    if result.success?
      redirect_to accounting_closing_run_path(result[:run]), notice: "The closing of #{year.year} is open: 18 steps."
    elsif result[:run]
      redirect_to accounting_closing_run_path(result[:run]), alert: result.message
    else
      redirect_to accounting_closing_runs_path, alert: result.message
    end
  end

  def show
    authorize @run
    Closing::Evaluate.call(run: @run)
    @steps = @run.steps.reload
    @drafts = Accounting::JournalEntry.where(closing_run_id: @run.id, status: :draft).includes(lines: %i[account partner]).order(:entry_date, :id)
    @summary = summary
    return unless @run.closed?

    @appropriation = Closing::Appropriation.proposal(@run)
    @appropriation_entry = Closing::Appropriation.entry_of(@run)
  end

  # The accounts the closing entries use and the thresholds of the analytical review: the owner's choice, as they decide what the books will say.
  def settings
    authorize Accounting::ClosingRun, :approve?
    entity = ActsAsTenant.current_tenant
    permitted = params.require(:entity).permit(:closing_result_account_code, :closing_carry_account_code, :review_threshold_pct, :review_threshold_amount)
    missing = %i[closing_result_account_code closing_carry_account_code].filter_map { |key| permitted[key] if permitted[key].present? && !Accounting::Account.exists?(code: permitted[key]) }
    return redirect_to(accounting_closing_runs_path, alert: "Account #{missing.to_sentence} does not exist in the chart of accounts.") if missing.any?

    if entity.update(permitted)
      redirect_to accounting_closing_runs_path, notice: "Closing settings saved."
    else
      redirect_to accounting_closing_runs_path, alert: entity.errors.full_messages.to_sentence
    end
  end

  # The appropriation of the result (legal reserve): a DRAFT of the next year, dated the day of the general meeting.
  def appropriate
    authorize @run, :update?
    result = Closing::Appropriation.call_prepare(run: @run, user: current_user, params: params)
    if result.success?
      redirect_to accounting_closing_run_path(@run), notice: "The appropriation is prepared as a draft of #{result[:entry].fiscal_year.year}: validate it when the meeting has decided."
    else
      redirect_to accounting_closing_run_path(@run), alert: result.message
    end
  end

  def validate_entries
    authorize @run, :update?
    result = Closing::ValidateEntries.call(run: @run, user: current_user)
    redirect_to accounting_closing_run_path(@run), (result.success? ? { notice: "#{result[:posted].size} closing entr#{result[:posted].size == 1 ? 'y' : 'ies'} validated." } : { alert: result.message })
  end

  def approve
    authorize @run, :approve?
    result = Closing::Approve.call(run: @run, user: current_user, comment: params[:comment])
    redirect_to accounting_closing_run_path(@run), (result.success? ? { notice: "The fiscal year #{@run.fiscal_year.year} is closed." } : { alert: result.message })
  end

  def reopen
    authorize @run, :reopen?
    result = Closing::Reopen.call(run: @run, user: current_user, reason: params[:reason])
    redirect_to accounting_closing_run_path(@run), (result.success? ? { notice: "The fiscal year #{@run.fiscal_year.year} is reopened. Close it again with a new run; the opening entry of the next year will be recalculated." } : { alert: result.message })
  end

  def bundle
    authorize @run, :show?
    return redirect_to(accounting_closing_run_path(@run), alert: "The closing file is made at step 17.") unless @run.bundle.attached?

    send_data @run.bundle.download, filename: "closing-#{@run.fiscal_year.year}.zip", type: "application/zip"
  end

  private

  def set_run = @run = Accounting::ClosingRun.find(params[:id])

  # The recap of the end: the result of the year, the balance sheet total, what the opening of the next year takes.
  def summary
    year = @run.fiscal_year
    report = Accounting::AnnualAccounts.new(fiscal_year: year).call
    income = report.rows(:income).find { |r| r.code == "9904" }&.amount
    total = report.rows(:assets).find { |r| r.code == "20/58" }&.amount
    opening = Accounting::JournalEntry.where(closing_run_id: @run.id, source_type: Accounting::JournalEntry::CARRY_FORWARD_SOURCE).where.not(status: :reversed).first
    { result: income, balance_sheet_total: total, opening_lines: opening&.lines&.count, opening_entry: opening }
  end
end
