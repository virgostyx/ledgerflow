class Accounting::Settings::BankAccountsController < Accounting::Settings::BaseController
  before_action :set_bank_account, only: [ :edit, :update, :destroy ]
  before_action :load_form_data,   only: [ :new, :create, :edit, :update ]

  def index
    @bank_accounts = Accounting::BankAccount
                       .includes(:journal, :transactions)
                       .order("accounting_journals.code")
  end

  def new
    @bank_account = Accounting::BankAccount.new
  end

  def create
    result = Accounting::Settings::AddBankAccount.call(
      params: bank_account_create_params,
      user:   current_user
    )

    if result.success?
      redirect_to accounting_settings_bank_accounts_path,
                  notice: t("accounting.settings.bank_accounts.created")
    else
      @bank_account = Accounting::BankAccount.new
      flash.now[:alert] = result.message
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @bank_account.update(bank_account_update_params)
      redirect_to accounting_settings_bank_accounts_path,
                  notice: t("accounting.settings.bank_accounts.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @bank_account.destroyable?
      @bank_account.destroy!
      redirect_to accounting_settings_bank_accounts_path,
                  notice: t("accounting.settings.bank_accounts.deleted")
    else
      redirect_to accounting_settings_bank_accounts_path,
                  alert: t("accounting.settings.bank_accounts.not_destroyable")
    end
  end

  private

  def set_bank_account
    @bank_account = Accounting::BankAccount.find(params[:id])
  end

  def load_form_data
    @accounts_55 = Accounting::Account
                     .where(active: true, is_leaf: true)
                     .where("code LIKE '55%'")
                     .order(:code)
  end

  def bank_account_create_params
    params.require(:bank_account_form).permit(
      :label_fr, :label_nl, :journal_code, :iban, :bic,
      :default_account_id, :currency, :notes
    ).to_h.symbolize_keys
  end

  def bank_account_update_params
    params.require(:accounting_bank_account).permit(
      :label_fr, :label_nl, :bic, :notes, :active
    )
  end
end
