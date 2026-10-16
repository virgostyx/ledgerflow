# The second factor is compulsory: enrolling an authenticator app (with backup codes), then a code at every sign-in.
class Portal::SecondFactorsController < Portal::BaseController
  skip_before_action :require_sign_in!
  before_action :require_password_step!

  def new
    return redirect_to(portal_root_path) if current_portal_user.second_factor_configured?

    @secret = current_portal_user.begin_totp_enrollment!
    @uri = Totp.provisioning_uri(@secret, account: current_portal_user.email, issuer: "Client portal")
  end

  def create
    user = current_portal_user
    if user.confirm_totp!(params[:code])
      user.update!(status: "active")
      current_portal_session.passed_second_factor!
      record_event("second_factor_enrolled")
      @backup_codes = user.generate_backup_codes!
      render :backup_codes
    else
      @secret = user.begin_totp_enrollment!
      @uri = Totp.provisioning_uri(@secret, account: user.email, issuer: "Client portal")
      flash.now[:alert] = "That code is not right. Try the next one your app shows."
      render :new, status: :unprocessable_content
    end
  end

  def challenge
    redirect_to(new_portal_second_factor_path) unless current_portal_user.second_factor_configured?
  end

  def verify
    user = current_portal_user
    if user.locked?
      end_session!
      return redirect_to(portal_sign_in_path)
    end

    method = if user.verify_totp!(params[:code]) then "totp" elsif user.use_backup_code!(params[:code]) then "backup_code" end
    if method
      user.register_success!
      current_portal_session.passed_second_factor!(method)
      record_event("second_factor_passed")
      redirect_to local_path(params[:return_to]) || portal_root_path
    else
      user.register_failure!
      record_event("second_factor_failed")
      flash.now[:alert] = "That code is not right."
      render :challenge, status: :unprocessable_content
    end
  end

  private

  # Where to go after the code, when a page sent the person here: a path of the portal, never an address elsewhere.
  def local_path(path)
    path.to_s if path.to_s.match?(%r{\A/[A-Za-z0-9_\-/]*\z}) && !path.to_s.start_with?("//")
  end

  # These pages are for someone who gave a password (or accepted an invitation): not for a visitor.
  def require_password_step!
    redirect_to(portal_sign_in_path) unless current_portal_session
  end
end
