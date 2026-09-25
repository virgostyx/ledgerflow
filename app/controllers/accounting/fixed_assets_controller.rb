class Accounting::FixedAssetsController < ApplicationController
  before_action :set_fixed_asset, only: [ :edit, :update, :destroy, :disposal, :dispose ]

  def index
    @pagy, @fixed_assets = pagy(policy_scope(Accounting::FixedAsset).includes(invoice_line: :invoice).order(acquisition_date: :desc))
    set_depreciation_rows
  end

  def post_depreciation
    authorize Accounting::FixedAsset

    result = Accounting::PostDepreciation.call(fiscal_year: Accounting::FiscalYear.find(params[:fiscal_year_id]))
    if result.failure?
      redirect_to accounting_fixed_assets_path, alert: result.message
    elsif result[:entries].empty?
      redirect_to accounting_fixed_assets_path, notice: t("accounting.fixed_assets.nothing_to_post")
    else
      redirect_to accounting_fixed_assets_path, notice: t("accounting.fixed_assets.depreciation_posted", count: result[:entries].size,
                                                          total: Accounting::MoneyPresenter.new(result[:total]).format)
    end
  end

  def new
    authorize Accounting::FixedAsset
    return prefill_from_invoice_line if params[:invoice_line_id].present?

    @fixed_asset = Accounting::FixedAsset.new
  end

  def create
    @fixed_asset = Accounting::FixedAsset.new(fixed_asset_params)
    authorize @fixed_asset

    if @fixed_asset.save
      redirect_to accounting_fixed_assets_path, notice: t("accounting.fixed_assets.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def disposal
    authorize @fixed_asset

    error = disposal_refusal
    redirect_to accounting_fixed_assets_path, alert: error if error
  end

  def dispose
    authorize @fixed_asset

    disposed_on = parsed_date(params[:disposed_on])
    return redirect_to disposal_accounting_fixed_asset_path(@fixed_asset), alert: t("accounting.fixed_assets.errors.invalid_date") unless disposed_on

    result = Accounting::DisposeFixedAsset.call(fixed_asset: @fixed_asset, disposed_on: disposed_on)
    if result.success?
      redirect_to accounting_fixed_assets_path,
                  notice: t("accounting.fixed_assets.disposed", value: Accounting::MoneyPresenter.new(result[:book_value]).format)
    else
      redirect_to disposal_accounting_fixed_asset_path(@fixed_asset), alert: result.message
    end
  end

  def edit
    authorize @fixed_asset
  end

  def update
    authorize @fixed_asset

    if @fixed_asset.update(fixed_asset_params)
      redirect_to accounting_fixed_assets_path, notice: t("accounting.fixed_assets.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @fixed_asset

    if @fixed_asset.destroy
      redirect_to accounting_fixed_assets_path, notice: t("accounting.fixed_assets.deleted")
    else
      redirect_to accounting_fixed_assets_path, alert: @fixed_asset.errors.full_messages.to_sentence
    end
  end

  private

  # The form of a new asset, prefilled from a purchase invoice line; or a redirect when the line cannot become one.
  def prefill_from_invoice_line
    line = Accounting::InvoiceLine.find_by(id: params[:invoice_line_id])
    return redirect_to accounting_fixed_assets_path, alert: t("accounting.fixed_assets.errors.line_not_found") unless line
    return redirect_to accounting_invoice_path(line.invoice), alert: t("accounting.fixed_assets.errors.not_an_asset_line") unless Accounting::FixedAsset.asset_purchase_line?(line)
    return redirect_to edit_accounting_fixed_asset_path(line.fixed_asset), notice: t("accounting.fixed_assets.errors.line_already_an_asset") if line.fixed_asset

    @fixed_asset = Accounting::FixedAsset.build_from_invoice_line(line)
  end

  def disposal_refusal
    return t("accounting.fixed_assets.errors.not_depreciable") unless @fixed_asset.depreciable?

    t("accounting.fixed_assets.errors.already_disposed") if @fixed_asset.disposed?
  end

  def parsed_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  # [[asset, amount, posted?], ...] for the open (or requested) fiscal year: what the depreciation posting will book or has booked.
  def set_depreciation_rows
    @fiscal_year = Accounting::FiscalYear.find_by(id: params[:fiscal_year_id]) || Accounting::FiscalYear.current
    @depreciation_rows = []
    return unless @fiscal_year

    posted = Accounting::DepreciationEntry.where(fiscal_year: @fiscal_year).index_by(&:fixed_asset_id)
    @depreciation_rows = Accounting::FixedAsset.includes(:asset_account).order(:description).filter_map do |asset|
      amount = posted[asset.id]&.amount || asset.depreciation_for(@fiscal_year)
      [ asset, amount, posted.key?(asset.id) ] if amount.positive?
    end
  end

  def set_fixed_asset
    @fixed_asset = Accounting::FixedAsset.find(params[:id])
  end

  def fixed_asset_params
    params.require(:accounting_fixed_asset).permit(
      :description, :acquisition_date, :vat_amount_initial,
      :prorata_at_acquisition, :asset_category, :disposed_on,
      :acquisition_value, :asset_account_id, :in_service_date, :useful_life_years, :residual_value, :invoice_line_id
    )
  end
end
