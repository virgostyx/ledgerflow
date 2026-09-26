module Users
  # Last resort for a passwordless user who lost their passkey.
  class RecoveryCodeSessionsController < ApplicationController
    layout "devise"
    skip_before_action :authenticate_user!

    def new; end

    def create
      user = User.find_by(email: params[:email].to_s.strip)

      if user&.passwordless? && user.active_for_authentication? && user.use_recovery_code!(params[:recovery_code])
        sign_in(user)
        redirect_to passkeys_path, notice: "Signed in with a recovery code. Please remove the lost passkey and register a new one."
      else
        flash.now[:alert] = "Invalid email or recovery code."
        render :new, status: :unprocessable_content
      end
    end
  end
end
