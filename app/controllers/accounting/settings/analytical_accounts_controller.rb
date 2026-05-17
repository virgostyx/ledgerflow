class Accounting::Settings::AnalyticalAccountsController < Accounting::Settings::BaseController
  before_action :set_axis,    only: [ :new, :create ]
  before_action :set_account, only: [ :edit, :update, :destroy ]

  def new
    @account = Accounting::AnalyticalAccount.new(analytical_axis: @axis)
  end

  def create
    @account = Accounting::AnalyticalAccount.new(account_params)
    @account.analytical_axis = @axis
    if @account.save
      redirect_to accounting_settings_analytical_axis_path(@axis),
                  notice: t("accounting.settings.analytical_accounts.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @account.update(account_params)
      redirect_to accounting_settings_analytical_axis_path(@account.analytical_axis),
                  notice: t("accounting.settings.analytical_accounts.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    axis = @account.analytical_axis
    if @account.destroyable?
      @account.destroy!
      redirect_to accounting_settings_analytical_axis_path(axis),
                  notice: t("accounting.settings.analytical_accounts.deleted")
    else
      redirect_to accounting_settings_analytical_axis_path(axis),
                  alert: t("accounting.settings.analytical_accounts.not_destroyable")
    end
  end

  private

  def set_axis
    @axis = Accounting::AnalyticalAxis.find(params[:analytical_axis_id])
  end

  def set_account
    @account = Accounting::AnalyticalAccount.find(params[:id])
  end

  def account_params
    params.require(:accounting_analytical_account).permit(:code, :label_fr, :label_nl, :active)
  end
end
