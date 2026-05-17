class Accounting::Settings::BaseController < ApplicationController
  layout "accounting/settings"

  before_action :authorize_settings_access!

  private

  def authorize_settings_access!
    unless current_user.admin? || current_user.accountant?
      flash[:alert] = t("errors.not_authorized")
      redirect_to accounting_root_path
    end
  end
end
