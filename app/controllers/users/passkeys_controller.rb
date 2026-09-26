module Users
  # Self-service passkey management. The first passkey makes the account
  # passwordless and generates one-time recovery codes (returned once).
  class PasskeysController < ApplicationController
    def index
      @webauthn_credentials = current_user.webauthn_credentials.order(:created_at)
    end

    def options
      creation_options = WebAuthn::Credential.options_for_create(
        user: { id: current_user.webauthn_id, name: current_user.email, display_name: current_user.full_name },
        exclude: current_user.webauthn_credentials.pluck(:external_id),
        authenticator_selection: { resident_key: "required", user_verification: "required" }
      )
      session[:webauthn_registration_challenge] = creation_options.challenge
      render json: creation_options
    end

    def create
      nickname = params[:nickname].to_s.strip
      return render_error("Please enter a name for this passkey.") if nickname.blank?

      webauthn_credential = WebAuthn::Credential.from_create(params[:credential])
      webauthn_credential.verify(session.delete(:webauthn_registration_challenge), user_verification: true)

      first = !current_user.passwordless?
      current_user.webauthn_credentials.create!(
        external_id: webauthn_credential.id, public_key: webauthn_credential.public_key,
        sign_count: webauthn_credential.sign_count, nickname: nickname
      )
      render json: { ok: true, backup_codes: (current_user.generate_recovery_codes! if first) }
    rescue WebAuthn::Error
      render_error("Passkey registration failed. Please try again.")
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages.to_sentence)
    end

    def destroy
      current_user.webauthn_credentials.find(params[:id]).destroy!
      if current_user.passwordless?
        redirect_to passkeys_path, notice: "Passkey removed."
      else
        current_user.recovery_codes.destroy_all
        redirect_to passkeys_path, notice: "Passkey removed. Password sign-in is available for your account again."
      end
    end

    private

    def render_error(message)
      render json: { error: message }, status: :unprocessable_content
    end
  end
end
