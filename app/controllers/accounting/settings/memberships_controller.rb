# F01: who has access to this entity and with which role, expiry date or deactivation. Owners only.
class Accounting::Settings::MembershipsController < Accounting::Settings::BaseController
  before_action { authorize UserEntity }

  def index
    @memberships = UserEntity.where(entity: current_entity).includes(:user).order(:id)
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
    if membership.update(params.require(:membership).permit(:role, :active, :valid_until))
      redirect_to accounting_settings_memberships_path, notice: t("entities.invite.updated")
    else
      redirect_to accounting_settings_memberships_path, alert: membership.errors.full_messages.to_sentence
    end
  end

  private

  def current_entity = ActsAsTenant.current_tenant
end
