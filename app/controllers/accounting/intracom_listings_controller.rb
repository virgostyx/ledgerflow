class Accounting::IntracomListingsController < ApplicationController
  before_action :set_listing, only: [ :show ]

  def index
    @pagy, @listings = pagy(policy_scope(Accounting::IntracomListing).filter_by(filter_params).order(period_start: :desc).autofilter(**autofilter_params))
  end

  def show
    authorize @listing
  end

  def new
    @listing = Accounting::IntracomListing.new
    @fiscal_years = Accounting::FiscalYear.all.order(start_date: :desc)
    authorize @listing
  end

  def create
    authorize Accounting::IntracomListing.new

    result = Accounting::GenerateIntracomListing.call(
      fiscal_year_id: listing_params[:fiscal_year_id].to_i,
      period_start:   Date.parse(listing_params[:period_start]),
      period_end:     Date.parse(listing_params[:period_end])
    )

    if result.success?
      redirect_to accounting_intracom_listing_path(result[:intracom_listing]),
                  notice: t("accounting.intracom_listings.created")
    else
      @listing = Accounting::IntracomListing.new(listing_params)
      @fiscal_years = Accounting::FiscalYear.all.order(start_date: :desc)
      flash.now[:alert] = result.message
      render :new, status: :unprocessable_content
    end
  rescue ArgumentError, TypeError
    @listing = Accounting::IntracomListing.new(listing_params)
    @fiscal_years = Accounting::FiscalYear.all.order(start_date: :desc)
    render :new, status: :unprocessable_content
  end

  private

  def set_listing
    @listing = Accounting::IntracomListing.find(params[:id])
  end

  def listing_params
    params.require(:accounting_intracom_listing).permit(:fiscal_year_id, :period_start, :period_end)
  end
end
