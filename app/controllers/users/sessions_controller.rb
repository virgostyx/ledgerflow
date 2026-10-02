class Users::SessionsController < Devise::SessionsController
  layout "devise"

  # Passwordless accounts (>= 1 passkey) cannot sign in with a password.
  def create
    user = User.find_by(email: params.dig(:user, :email).to_s.strip)
    if user&.valid_password?(params.dig(:user, :password)) && user.passwordless?
      sign_out(:user) # ApplicationController#current_user already authenticated from the params
      flash.now[:alert] = "This account signs in with a passkey. Use the passkey button or a recovery code."
      self.resource = resource_class.new(sign_in_params)
      return render :new, status: :unprocessable_content
    end
    super { |resource| Accounting::AuditLogin.call(user: resource, action: "login", method: "password") }
  end

  protected

  def after_sign_in_path_for(resource)
    accounting_root_path
  end

  def after_sign_out_path_for(resource_or_scope)
    root_path
  end
end
