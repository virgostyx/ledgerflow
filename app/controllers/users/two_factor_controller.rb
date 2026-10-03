module Users
  # F01: second factor (TOTP). `show`/`create`/`destroy` enrol, confirm and switch it off; `challenge`/`verify` are the
  # step after the password. A passkey needs no challenge (see PasskeySessionsController).
  class TwoFactorController < ApplicationController
    layout "devise"
    skip_before_action :require_second_factor!

    def show
      return render(:enabled) if current_user.totp_enabled?

      prepare_enrolment
    end

    def create
      if current_user.confirm_totp!(params[:code])
        second_factor_passed!
        Accounting::AuditLogin.call(user: current_user, action: "two_factor_enabled", method: "totp")
        @continue_path = session.delete(:after_second_factor_path) || accounting_root_path
        @codes = current_user.generate_totp_backup_codes!
        render :backup_codes
      else
        prepare_enrolment
        flash.now[:alert] = t("users.two_factor.wrong_code")
        render :show, status: :unprocessable_content
      end
    end

    def destroy
      if current_user.second_factor_required?
        redirect_to two_factor_path, alert: t("users.two_factor.required_for_role")
      elsif current_user.verify_totp!(params[:code])
        current_user.disable_totp!
        Accounting::AuditLogin.call(user: current_user, action: "two_factor_disabled", method: "totp")
        redirect_to two_factor_path, notice: t("users.two_factor.disabled")
      else
        redirect_to two_factor_path, alert: t("users.two_factor.wrong_code")
      end
    end

    # New backup codes, the old ones stop working; the person proves it with a current code.
    def backup_codes
      return redirect_to(two_factor_path, alert: t("users.two_factor.wrong_code")) unless current_user.verify_totp!(params[:code])

      @continue_path = accounting_root_path
      @codes = current_user.generate_totp_backup_codes!
      render :backup_codes
    end

    def challenge
      redirect_to(two_factor_path) unless current_user.totp_enabled?
    end

    def verify
      if current_user.verify_totp!(params[:code])
        second_factor_passed!
        redirect_to session.delete(:after_second_factor_path) || accounting_root_path
      elsif current_user.use_totp_backup_code!(params[:code])
        second_factor_passed!
        Accounting::AuditLogin.call(user: current_user, action: "two_factor_backup_code_used", method: "totp")
        redirect_to session.delete(:after_second_factor_path) || accounting_root_path, alert: t("users.two_factor.backup_code_used")
      else
        Accounting::AuditLogin.call(user: current_user, action: "login_failed", method: "totp")
        flash.now[:alert] = t("users.two_factor.wrong_code")
        render :challenge, status: :unprocessable_content
      end
    end

    private

    def prepare_enrolment
      secret  = current_user.begin_totp_enrollment!
      @secret = secret.scan(/.{1,4}/).join(" ")
      @uri    = Totp.provisioning_uri(secret, account: current_user.email, issuer: "LedgerFlow")
      @qr_svg = RQRCode::QRCode.new(@uri).as_svg(module_size: 4, standalone: true, use_path: true, viewbox: true)
    end
  end
end
