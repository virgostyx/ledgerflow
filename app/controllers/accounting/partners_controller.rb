class Accounting::PartnersController < ApplicationController
  before_action :set_partner, only: [ :show, :edit, :update, :destroy ]

  def index
    @partners = policy_scope(Accounting::Partner).active.order(:name)
  end

  def show
    authorize @partner
  end

  def new
    @partner = Accounting::Partner.new
    authorize @partner
  end

  def create
    @partner = Accounting::Partner.new(partner_params)
    authorize @partner

    if @partner.save
      redirect_to accounting_partners_path, notice: t("accounting.partners.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @partner
  end

  def update
    authorize @partner

    if @partner.update(partner_params)
      redirect_to accounting_partner_path(@partner), notice: t("accounting.partners.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @partner
    @partner.destroy!
    redirect_to accounting_partners_path, notice: t("accounting.partners.deleted")
  end

  private

  def set_partner
    @partner = Accounting::Partner.find(params[:id])
  end

  def partner_params
    params.require(:accounting_partner).permit(
      :name, :partner_type, :vat_number, :email, :phone,
      :street, :city, :zip, :country, :iban, :bic, :active, :notes
    )
  end
end
