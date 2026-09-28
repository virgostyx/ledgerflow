# R17 closing regularizations (docs/dev/reports/spec.md §13): the report with its I11 checks and cut-off lists,
# plus the creation of accruals and the (draft) booking and reversal entries.
class Accounting::AccrualsController < ApplicationController
  before_action :set_fiscal_year
  before_action :set_accrual, only: [ :destroy, :book, :reverse ]

  def index
    authorize Accounting::Accrual
    @fiscal_years = Accounting::FiscalYear.order(start_date: :desc)
    @result = Accounting::AccrualsReportQuery.new(fiscal_year: @fiscal_year).call if @fiscal_year
  end

  def new
    authorize Accounting::Accrual
    @accrual = Accounting::Accrual.new(fiscal_year: @fiscal_year, accrual_type: :deferred_charge,
                                       period_start: @fiscal_year&.end_date, period_end: @fiscal_year&.end_date)
    load_accounts
  end

  def create
    authorize Accounting::Accrual
    @accrual = Accounting::Accrual.new(accrual_params.merge(fiscal_year: @fiscal_year))
    @accrual.accrual_account ||= Accounting::Account.find_by(code: Accounting::Accrual::ACCOUNT_CODES[@accrual.accrual_type.to_sym]) if @accrual.accrual_type
    if @accrual.save
      redirect_to accounting_accruals_path(fiscal_year_id: @fiscal_year.id), notice: "Regularization added."
    else
      load_accounts
      render :new, status: :unprocessable_content
    end
  end

  def book
    authorize @accrual
    redirect_with Accounting::BookAccrual.call(accrual: @accrual), "Draft entry generated: validate it in the journal entries."
  end

  def reverse
    authorize @accrual
    redirect_with Accounting::ReverseAccrual.call(accrual: @accrual), "Draft reversal generated in the next fiscal year."
  end

  def destroy
    authorize @accrual
    if @accrual.booked?
      redirect_to accounting_accruals_path(fiscal_year_id: @accrual.fiscal_year_id), alert: "A booked regularization cannot be deleted."
    else
      @accrual.destroy!
      redirect_to accounting_accruals_path(fiscal_year_id: @accrual.fiscal_year_id), notice: "Regularization deleted."
    end
  end

  private

  def redirect_with(result, notice)
    path = accounting_accruals_path(fiscal_year_id: @accrual.fiscal_year_id)
    result.success? ? redirect_to(path, notice: notice) : redirect_to(path, alert: result.message)
  end

  def set_fiscal_year
    @fiscal_year = Accounting::FiscalYear.find_by(id: params[:fiscal_year_id]) || Accounting::FiscalYear.current || Accounting::FiscalYear.order(:start_date).last
  end

  def set_accrual
    @accrual = Accounting::Accrual.find(params[:id])
  end

  def load_accounts
    @pl_accounts = Accounting::Account.active.leaf.where(account_class: [ 6, 7 ]).order(:code)
  end

  def accrual_params
    params.require(:accounting_accrual).permit(:accrual_type, :description, :total_amount, :period_start, :period_end,
                                               :pl_account_id, :source_journal_entry_id)
  end
end
