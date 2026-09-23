class Accounting::FiscalYearsController < ApplicationController
  before_action :set_fiscal_year, only: [
    :show, :edit, :update, :destroy, :close,
    :vat_regularization, :regularize_prorata, :review_fixed_assets
  ]

  def index
    @pagy, @fiscal_years = pagy(policy_scope(Accounting::FiscalYear).order(year: :desc).autofilter(**autofilter_params))
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

  def vat_regularization
    authorize @fiscal_year, :vat_regularization?

    @suggested_prorata_rate = suggested_prorata_rate
    @fixed_assets = under_review_fixed_assets
  end

  def regularize_prorata
    authorize @fiscal_year, :vat_regularization?

    result = Accounting::Actions::RegularizeVatProrata.call(
      fiscal_year_id: @fiscal_year.id, final_prorata_rate: BigDecimal(params[:final_prorata_rate])
    )

    if result.success?
      notice = result[:journal_entry] ? t("accounting.fiscal_years.vat_regularization.prorata_regularized") :
                                         t("accounting.fiscal_years.vat_regularization.no_adjustment_needed")
      redirect_to vat_regularization_accounting_fiscal_year_path(@fiscal_year), notice: notice
    else
      redirect_to vat_regularization_accounting_fiscal_year_path(@fiscal_year), alert: result.message
    end
  rescue ArgumentError, TypeError
    redirect_to vat_regularization_accounting_fiscal_year_path(@fiscal_year),
                alert: t("accounting.fiscal_years.vat_regularization.invalid_rate")
  end

  def review_fixed_assets
    authorize @fiscal_year, :vat_regularization?

    rate = BigDecimal(params[:final_prorata_rate])
    assets = under_review_fixed_assets
    reviewed_count = assets.count do |asset|
      result = Accounting::Actions::ReviewFixedAssetVat.call(
        fixed_asset: asset, fiscal_year: @fiscal_year, final_prorata_rate: rate
      )
      result.success? && result[:journal_entry].present?
    end

    redirect_to vat_regularization_accounting_fiscal_year_path(@fiscal_year),
                notice: t("accounting.fiscal_years.vat_regularization.assets_reviewed",
                          count: reviewed_count, total: assets.size)
  rescue ArgumentError, TypeError
    redirect_to vat_regularization_accounting_fiscal_year_path(@fiscal_year),
                alert: t("accounting.fiscal_years.vat_regularization.invalid_rate")
  end

  private

  def set_fiscal_year
    @fiscal_year = Accounting::FiscalYear.find(params[:id])
  end

  def fiscal_year_params
    params.require(:accounting_fiscal_year).permit(:year, :start_date, :end_date)
  end

  def under_review_fixed_assets
    Accounting::FixedAsset.all.select { |asset| asset.under_review?(@fiscal_year.year) }
  end

  # Suggested final prorata: taxed sale base grids over total (taxed + exempt) sale base grids,
  # from the year's already-filed VAT declarations. Left editable — never applied silently.
  def suggested_prorata_rate
    exempt_grid = Accounting::VatGrid::TREATMENT_BASE_GRID[:sale][:exempt].to_s
    taxed, total = BigDecimal("0"), BigDecimal("0")

    Accounting::VatDeclaration.where(fiscal_year: @fiscal_year).find_each do |declaration|
      declaration.grids.each do |code, amount|
        next unless Accounting::VatGrid::RATE_TO_GRID[:sale].value?(code.to_i) ||
                   Accounting::VatGrid::TREATMENT_BASE_GRID[:sale].value?(code.to_i)
        amount = BigDecimal(amount)
        total += amount
        taxed += amount unless code == exempt_grid
      end
    end

    return nil if total.zero?
    (taxed / total * 100).round(2)
  end
end
