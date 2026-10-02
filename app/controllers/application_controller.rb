class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes
  set_current_tenant_through_filter

  before_action :authenticate_user!
  before_action :require_second_factor!
  before_action :set_audit_context
  before_action :set_locale
  before_action :set_current_entity
  before_action :require_entity!

  include Pundit::Authorization
  include Pagy::Backend

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  helper_method :filter_params, :filters_active?, :autofilter_params, :budgetflow_enabled?, :feature?

  private

  # Who / where / which request, read by the audit trail (Accounting::AuditLog.record!).
  def set_audit_context
    Current.user       = current_user
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent.to_s.first(255)
    Current.request_id = request.request_id
  end

  FILTER_KEYS = %i[q status journal_id fiscal_year_id partner_type country from to overdue unpaid
                   inactive period_type bank_account_id direction source].freeze

  # List filters, submitted as q[...] by shared/_filters.
  def filter_params
    params[:q].is_a?(ActionController::Parameters) ? params[:q].permit(*FILTER_KEYS) : ActionController::Parameters.new.permit
  end

  def filters_active?
    filter_params.values.any?(&:present?) || params[:f].present?
  end

  # Per-column filters/sort (f[col]=..., sort=col, dir=asc|desc), whitelisted by the model's `autofilter_column`s.
  def autofilter_params
    { sort: params[:sort].to_s, dir: params[:dir].to_s,
      f: params[:f].respond_to?(:to_unsafe_h) ? params[:f].to_unsafe_h : {} }
  end

  def set_locale
    I18n.locale = I18n.default_locale
  end

  # Whether the current entity declared the BudgetFlow integration; everything BudgetFlow-related hangs on it.
  def budgetflow_enabled? = ActsAsTenant.current_tenant&.budgetflow? || false

  # Whether a feature (docs/dev/features/spec.md) is turned on for the current entity.
  def feature?(name) = ActsAsTenant.current_tenant&.feature?(name) || false

  # F01: after the password, a person who enrolled a second factor is asked for a code, and one whose role requires
  # it must enrol first. A passkey counts as the second factor (see PasskeySessionsController).
  def require_second_factor!
    return unless current_user && Rails.configuration.x.second_factor_required
    return if devise_controller? || second_factor_passed?

    if current_user.totp_enabled?
      session[:after_second_factor_path] = request.fullpath if request.get?
      redirect_to two_factor_challenge_path
    elsif current_user.second_factor_required?
      redirect_to two_factor_path, alert: t("errors.second_factor_required")
    end
  end

  # Tied to the user, so one person's verification never serves another's session.
  def second_factor_passed? = session[:second_factor_user_id] == current_user.id

  def second_factor_passed!(user = current_user) = session[:second_factor_user_id] = user.id

  # The name stamped on the PDFs an external auditor downloads (F01); nil for every other role.
  def export_watermark
    membership = UserEntity.current.find_by(user: current_user, entity: ActsAsTenant.current_tenant)
    current_user.full_name if membership&.auditor?
  end

  # A screen of a feature that is off is closed, not hidden by chance: the guard is on the server.
  def require_feature!(name)
    return if feature?(name)

    redirect_to accounting_root_path, alert: t("errors.feature_off")
  end

  def set_current_entity
    return unless current_user
    entity_id = session[:current_entity_id]
    entity = entity_id ? current_user.current_entities.find_by(id: entity_id) : nil
    entity ||= current_user.current_entities.active.first
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
