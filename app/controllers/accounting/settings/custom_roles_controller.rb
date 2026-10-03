# F01: the roles an owner composes from the fine permissions. Owners only; closed while the feature is off.
class Accounting::Settings::CustomRolesController < Accounting::Settings::BaseController
  before_action { require_feature!(:f01) }
  before_action { authorize CustomRole }

  def index
    @roles = CustomRole.order(:name)
    @role  = CustomRole.new
  end

  def create
    role = CustomRole.new(role_params)
    redirect_back_with(role.save, role, t("accounting.settings.custom_roles.created"))
  end

  def update
    role = CustomRole.find(params[:id])
    redirect_back_with(role.update(role_params), role, t("accounting.settings.custom_roles.updated"))
  end

  def destroy
    role = CustomRole.find(params[:id])
    redirect_back_with(role.destroy, role, t("accounting.settings.custom_roles.deleted"))
  end

  private

  def role_params = params.require(:custom_role).permit(:name, permissions: [])

  def redirect_back_with(ok, role, notice)
    if ok
      redirect_to accounting_settings_custom_roles_path, notice: notice
    else
      redirect_to accounting_settings_custom_roles_path, alert: role.errors.full_messages.to_sentence
    end
  end
end
