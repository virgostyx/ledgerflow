# B02a: the base of every page of the client portal. It does not inherit from ApplicationController: no Devise, no tenant, nothing of the application.
# What a person from outside sees is what the firm published (Portal::Publication), read through the scope of their grant, never the books.
class Portal::BaseController < ActionController::Base
  layout "portal/application"

  # No Rails session at all on this host: the forgery token lives in a cookie of its own, the person's session in the database.
  protect_from_forgery with: :exception, store: :cookie

  content_security_policy do |policy|
    policy.default_src     :none
    policy.script_src      :self
    policy.style_src       :self
    policy.img_src         :self
    policy.font_src        :self
    policy.connect_src     :self
    policy.form_action     :self
    policy.base_uri        :none
    policy.frame_ancestors :none
  end

  before_action :set_security_headers
  before_action :require_sign_in!
  helper_method :current_portal_user, :current_portal_session

  COOKIE = :lf_portal

  private

  def current_portal_session
    return @current_portal_session if defined?(@current_portal_session)

    @current_portal_session = Portal::Session.authenticate(cookies.encrypted[COOKIE])
  end

  def current_portal_user = current_portal_session&.portal_user

  # Nothing opens without a live session, a second factor configured and a second factor given in this session.
  def require_sign_in!
    return redirect_to(portal_sign_in_path) unless current_portal_session
    return redirect_to(new_portal_second_factor_path) unless current_portal_user.second_factor_configured?

    redirect_to(portal_second_factor_challenge_path) unless current_portal_session.second_factor_at
  end

  def start_session!(user)
    session, token = Portal::Session.start!(user, ip: request.remote_ip, user_agent: request.user_agent)
    cookies.encrypted[COOKIE] = { value: token, httponly: true, secure: request.ssl?, same_site: :lax }
    @current_portal_session = session
  end

  def end_session!
    current_portal_session&.revoke!
    cookies.delete(COOKIE)
    @current_portal_session = nil
  end

  # An identifier that is not in the scope of the person looks like one that does not exist; the attempt is noted.
  def not_in_scope(token)
    record_event("out_of_scope_attempt", target_token: token.to_s.first(64))
    head :not_found
  end

  def record_event(action, **attributes)
    Portal::Event.record!(action, request: request, user: current_portal_user, **attributes)
  end

  def set_security_headers
    response.set_header("Cache-Control", "no-store")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Content-Type-Options", "nosniff")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    response.set_header("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()")
    response.set_header("Cross-Origin-Opener-Policy", "same-origin")
  end
end
