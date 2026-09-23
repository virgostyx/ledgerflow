class Accounting::FixedAssetsController < ApplicationController
  before_action :set_fixed_asset, only: [ :edit, :update, :destroy ]

  def index
    @pagy, @fixed_assets = pagy(policy_scope(Accounting::FixedAsset).order(acquisition_date: :desc))
  end

  def new
    @fixed_asset = Accounting::FixedAsset.new
    authorize @fixed_asset
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
    @fixed_asset.destroy!
    redirect_to accounting_fixed_assets_path, notice: t("accounting.fixed_assets.deleted")
  end

  private

  def set_fixed_asset
    @fixed_asset = Accounting::FixedAsset.find(params[:id])
  end

  def fixed_asset_params
    params.require(:accounting_fixed_asset).permit(
      :description, :acquisition_date, :vat_amount_initial,
      :prorata_at_acquisition, :asset_category, :disposed_on
    )
  end
end
