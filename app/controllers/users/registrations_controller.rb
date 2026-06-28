class Users::RegistrationsController < Devise::RegistrationsController
  layout "devise"

  protected

  def after_sign_up_path_for(_resource)
    new_onboarding_entity_path
  end

  def after_inactive_sign_up_path_for(_resource)
    new_onboarding_entity_path
  end

  private

  def sign_up_params
    params.require(:user).permit(:full_name, :email, :password, :password_confirmation)
  end

  def account_update_params
    params.require(:user).permit(:full_name, :email, :password,
                                 :password_confirmation, :current_password)
  end
end
