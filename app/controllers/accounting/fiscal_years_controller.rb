class Accounting::FiscalYearsController < ApplicationController
  before_action :set_fiscal_year, only: [ :show, :edit, :update, :destroy, :close ]

  def index
    @fiscal_years = policy_scope(Accounting::FiscalYear).order(year: :desc)
  end

  def show
    authorize @fiscal_year
  end

  def new
    @fiscal_year = Accounting::FiscalYear.new
    authorize @fiscal_year
  end

  def create
    @fiscal_year = Accounting::FiscalYear.new(fiscal_year_params)
    authorize @fiscal_year

    if @fiscal_year.save
      Accounting::CarryForwardBalances.call(
        new_fiscal_year: @fiscal_year,
        closed_by:       current_user
      )
      redirect_to accounting_fiscal_year_path(@fiscal_year),
                  notice: t("accounting.fiscal_years.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @fiscal_year
  end

  def update
    authorize @fiscal_year

    if @fiscal_year.update(fiscal_year_params)
      redirect_to accounting_fiscal_year_path(@fiscal_year),
                  notice: t("accounting.fiscal_years.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    head :forbidden
  end

  def close
    authorize @fiscal_year, :close?

    result = Accounting::CloseFiscalYear.call(
      fiscal_year: @fiscal_year,
      closed_by:   current_user
    )

    if result.success?
      redirect_to accounting_fiscal_year_path(@fiscal_year),
                  notice: t("accounting.fiscal_years.closed")
    else
      redirect_to accounting_fiscal_year_path(@fiscal_year),
                  alert: result.message
    end
  end

  private

  def set_fiscal_year
    @fiscal_year = Accounting::FiscalYear.find(params[:id])
  end

  def fiscal_year_params
    params.require(:accounting_fiscal_year).permit(:year, :start_date, :end_date)
  end
end
