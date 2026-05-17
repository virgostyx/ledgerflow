class Accounting::Settings::AccountsController < Accounting::Settings::BaseController
  before_action :set_account, only: [ :edit, :update ]

  def index
    @accounts = if params[:account_class].present?
      Accounting::Account.by_class(params[:account_class]).order(:code)
    else
      Accounting::Account.order(:code)
    end
  end

  def new
    @parent  = Accounting::Account.find_by(id: params[:parent_id])
    @account = Accounting::Account.new(parent: @parent)
  end

  def create
    result = Accounting::Settings::CreateCustomAccount.call(
      params: account_params,
      user:   current_user
    )

    if result.success?
      redirect_to accounting_settings_accounts_path(account_class: result[:account].account_class),
                  notice: t("accounting.settings.accounts.created")
    else
      @parent  = Accounting::Account.find_by(id: account_params[:parent_id])
      @account = Accounting::Account.new(account_params.except(:parent_id))
      @account.errors.add(:base, result.message)
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @account.update(update_params)
      redirect_to accounting_settings_accounts_path(account_class: @account.account_class),
                  notice: t("accounting.settings.accounts.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_account
    @account = Accounting::Account.find(params[:id])
  end

  def account_params
    params.require(:accounting_account).permit(
      :parent_id, :code, :label_fr, :label_nl,
      :account_class, :account_type, :normal_balance
    ).to_h.symbolize_keys
  end

  def update_params
    params.require(:accounting_account).permit(:label_fr, :label_nl, :active)
  end
end
