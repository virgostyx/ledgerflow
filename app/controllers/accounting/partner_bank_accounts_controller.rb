# B01b: the bank accounts of the suppliers. Listed (masked) for whoever reads records; registered by a person who writes them; verified by another person who may
# (bank_accounts.verify) and sees the full IBAN to compare it with what the supplier said on the phone; blocked with a reason. Nothing here is reached by a document.
class Accounting::PartnerBankAccountsController < ApplicationController
  before_action { require_feature!(:b01b) }
  before_action :set_account, only: %i[show verify block]

  def index
    authorize Accounting::PartnerBankAccount
    accounts = Accounting::PartnerBankAccount.includes(:partner, :created_by, :verified_by)
    @to_verify = accounts.unverified.order(:created_at)
    @in_use    = accounts.verified.order(:verified_at)
    @over      = accounts.where(status: %i[blocked superseded]).order(updated_at: :desc).limit(100)
    @to_register = Accounting::Partner.supplier.where(active: true).where.not(iban: [ nil, "" ]).where.not(id: Accounting::PartnerBankAccount.live.select(:partner_id)).order(:name)
  end

  def new
    authorize Accounting::PartnerBankAccount, :register?
    @account = Accounting::PartnerBankAccount.new(partner_id: params[:partner_id])
    load_partners
  end

  def create
    authorize Accounting::PartnerBankAccount, :register?
    attrs = params.require(:partner_bank_account).permit(:partner_id, :iban, :holder_name, :bic)
    partner = Accounting::Partner.supplier.find(attrs[:partner_id])
    result = Payments::RegisterBankAccount.call(partner: partner, iban: attrs[:iban], holder_name: attrs[:holder_name], bic: attrs[:bic], user: current_user)
    if result.success?
      redirect_to accounting_partner_bank_account_path(result[:account]), notice: t("payments.bank_accounts.registered")
    else
      @account = Accounting::PartnerBankAccount.new(attrs.except(:iban).merge(iban: attrs[:iban]))
      load_partners
      flash.now[:alert] = result.message
      render :new, status: :unprocessable_content
    end
  end

  # The IBAN written on the record of a supplier, registered on one click by a person (it is still unverified and observed).
  def register_from_partner
    authorize Accounting::PartnerBankAccount, :register?
    partner = Accounting::Partner.supplier.find(params[:partner_id])
    result = Payments::RegisterBankAccount.call(partner: partner, iban: partner.iban, holder_name: partner.name, user: current_user)
    if result.success?
      redirect_to accounting_partner_bank_account_path(result[:account]), notice: t("payments.bank_accounts.registered")
    else
      redirect_to accounting_partner_bank_accounts_path, alert: result.message
    end
  end

  def show
    authorize @account
    @full_iban = policy(@account).verify?
    @history = Accounting::AuditLog.for_record(@account).chronologic.includes(:user)
  end

  def verify
    authorize @account
    result = Payments::VerifyBankAccount.call(account: @account, user: current_user, method: params[:method].presence, note: params[:note])
    redirect_to accounting_partner_bank_account_path(@account), result.success? ? { notice: t("payments.bank_accounts.verified") } : { alert: result.message }
  end

  def block
    authorize @account
    result = Payments::BlockBankAccount.call(account: @account, user: current_user, reason: params[:reason])
    redirect_to accounting_partner_bank_account_path(@account), result.success? ? { notice: t("payments.bank_accounts.blocked") } : { alert: result.message }
  end

  private

  def set_account = (@account = Accounting::PartnerBankAccount.find(params[:id]))

  def load_partners = (@partners = Accounting::Partner.supplier.where(active: true).order(:name))
end
