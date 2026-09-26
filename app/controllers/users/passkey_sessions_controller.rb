module Users
  # Passwordless sign-in with a discoverable credential: the assertion's
  # userHandle identifies the user.
  class PasskeySessionsController < ApplicationController
    skip_before_action :authenticate_user!

    def options
      request_options = WebAuthn::Credential.options_for_get(user_verification: "required")
      session[:webauthn_authentication_challenge] = request_options.challenge
      render json: request_options
    end

    def create
      webauthn_credential = WebAuthn::Credential.from_get(params[:credential])
      stored = WebauthnCredential.find_by(external_id: webauthn_credential.id)
      return invalid_credential! unless stored

      user = stored.user
      handle = webauthn_credential.user_handle
      return invalid_credential! unless handle && ActiveSupport::SecurityUtils.secure_compare(handle, user.webauthn_id)
      return invalid_credential! unless user.active_for_authentication?

      webauthn_credential.verify(
        session.delete(:webauthn_authentication_challenge),
        public_key: stored.public_key, sign_count: stored.sign_count, user_verification: true
      )
      stored.update!(sign_count: webauthn_credential.sign_count, last_used_at: Time.current)
      sign_in(user)
      render json: { redirect_to: accounting_root_path }
    rescue WebAuthn::SignCountVerificationError
      render json: { error: "This passkey failed a security check and can't be used. Please contact support." }, status: :unprocessable_content
    rescue WebAuthn::Error
      invalid_credential!
    end

    private

    def invalid_credential!
      render json: { error: "Passkey sign-in failed. Please try again or use a recovery code." }, status: :unprocessable_content
    end
  end
end
