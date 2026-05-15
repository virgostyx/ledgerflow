class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :set_locale

  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def set_locale
    I18n.locale = current_user&.locale || :fr
  end

  def user_not_authorized
    flash[:alert] = t("errors.not_authorized")
    redirect_back(fallback_location: accounting_root_path)
  end
end
