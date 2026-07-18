class Accounting::Settings::AnalyticalAxesController < Accounting::Settings::BaseController
  before_action :set_axis, only: [ :show, :edit, :update ]

  def index
    @axes = Accounting::AnalyticalAxis.includes(:analytical_accounts).ordered
  end

  def show
    redirect_to edit_accounting_settings_analytical_axis_path(@axis)
  end

  def edit; end

  def update
    if @axis.update(axis_params)
      redirect_to accounting_settings_analytical_axes_path,
                  notice: t("accounting.settings.analytical_axes.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_axis
    @axis = Accounting::AnalyticalAxis.find(params[:id])
  end

  def axis_params
    params.require(:accounting_analytical_axis).permit(
      :label_fr, :label_nl, :active, required_for_account_classes: []
    ).tap do |permitted|
      permitted[:required_for_account_classes]&.reject!(&:blank?)
    end
  end
end
