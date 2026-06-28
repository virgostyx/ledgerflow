class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes
  set_current_tenant_through_filter

  before_action :authenticate_user!
  before_action :set_locale
  before_action :set_current_entity
  before_action :require_entity!

  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def set_locale
    I18n.locale = current_user&.locale || :fr
  end

  def set_current_entity
    return unless current_user
    entity_id = session[:current_entity_id]
    entity = entity_id ? current_user.entities.find_by(id: entity_id) : nil
    entity ||= current_user.entities.active.first
    set_current_tenant(entity)
    session[:current_entity_id] = entity&.id
  end

  def require_entity!
    return unless current_user
    return if devise_controller?
    return if ActsAsTenant.current_tenant.present?
    return if onboarding_path?
    redirect_to "/onboarding/entity/new", notice: t("entities.create_first_entity")
  end

  def onboarding_path?
    request.path.start_with?("/onboarding")
  end

  def user_not_authorized
    flash[:alert] = t("errors.not_authorized")
    redirect_back(fallback_location: accounting_root_path)
  end
end
