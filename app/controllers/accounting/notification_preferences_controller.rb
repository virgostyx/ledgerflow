# F08: what the current user wants to be sent by e-mail (their own access to the entity; the application always lists them).
class Accounting::NotificationPreferencesController < ApplicationController
  before_action { require_feature!(:f08) }
  before_action :set_membership

  def edit; end

  def update
    @membership.update!(params.require(:user_entity).permit(:notify_by_email, :notify_daily_digest))
    redirect_to edit_accounting_notification_preferences_path, notice: t("accounting.tasks.preferences_saved")
  end

  private

  def set_membership = @membership = UserEntity.current.find_by!(user: current_user, entity: ActsAsTenant.current_tenant)
end
