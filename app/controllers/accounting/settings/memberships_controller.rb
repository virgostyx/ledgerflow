# F01: who has access to this entity and with which role, expiry date or deactivation. Owners only.
class Accounting::Settings::MembershipsController < Accounting::Settings::BaseController
  before_action { require_feature!(:f01) }
  before_action { authorize UserEntity }

  def index
    @memberships = UserEntity.where(entity: current_entity).includes(:user).order(:id)
    @journals = Accounting::Journal.order(:code)
    @custom_roles = CustomRole.order(:name)
  end

  def create
    attrs = params.require(:membership).permit(:email, :full_name, :role, :valid_until)
    result = Entities::InviteMember.call(entity: current_entity, invited_by: current_user, **attrs.to_h.symbolize_keys)
    if result.success?
      redirect_to accounting_settings_memberships_path, notice: t("entities.invite.done")
    else
      redirect_to accounting_settings_memberships_path, alert: result.message
    end
  end

  def update
    membership = UserEntity.where(entity: current_entity).find(params[:id])
    attrs = params.require(:membership).permit(:role, :active, :valid_until, journal_ids: [])
    if attrs.key?(:role)
      role = role_attributes(attrs[:role])
      return redirect_to(accounting_settings_memberships_path, alert: t("accounting.settings.custom_roles.unknown")) unless role

      attrs = attrs.to_h.merge(role)
    end
    if membership.update(attrs)
      redirect_to accounting_settings_memberships_path, notice: t("entities.invite.updated")
    else
      redirect_to accounting_settings_memberships_path, alert: membership.errors.full_messages.to_sentence
    end
  end

  # An owner resets someone else's second factor (lost phone): switched off, backup codes removed, reason kept in the audit.
  # A role that requires it makes the person enrol again at their next request.
  def reset_two_factor
    membership = UserEntity.where(entity: current_entity).find(params[:id])
    reason = params[:reason].to_s.strip
    return redirect_to(accounting_settings_memberships_path, alert: t("users.two_factor.cannot_reset_own")) if membership.user_id == current_user.id
    return redirect_to(accounting_settings_memberships_path, alert: t("users.two_factor.reset_reason_required")) if reason.blank?

    ApplicationRecord.transaction do
      membership.user.disable_totp!
      Accounting::AuditLog.record!(auditable: membership.user, action: "two_factor_reset", user: current_user, reason: reason, payload: { email: membership.user.email })
    end
    redirect_to accounting_settings_memberships_path, notice: t("users.two_factor.reset")
  end

  private

  # The role select carries a system role ("accountant") or a custom role ("custom:12"). A custom role sits on top of the
  # least-privileged system role: the system role is then only a fallback, never what grants rights.
  def role_attributes(value)
    return { role: value, custom_role_id: nil } unless value.to_s.start_with?("custom:")

    custom = CustomRole.find_by(id: value.to_s.delete_prefix("custom:"))
    custom && { role: "manager", custom_role_id: custom.id }
  end

  def current_entity = ActsAsTenant.current_tenant
end
