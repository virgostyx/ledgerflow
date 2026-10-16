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

  around_action :on_the_portal_database
  before_action :set_security_headers
  before_action :require_sign_in!
  helper_method :current_portal_user, :current_portal_session, :portal_brand

  COOKIE = :lf_portal
  DEVICE_COOKIE = :lf_portal_device

  private

  # With a role of its own, everything a portal page reads or writes goes through it: a query on anything but the portal's tables is refused by the database.
  def on_the_portal_database(&)
    Portal.restricted_database? ? ApplicationRecord.connected_to(role: :portal, &) : yield
  end

  def current_portal_session
    return @current_portal_session if defined?(@current_portal_session)

    @current_portal_session = Portal::Session.authenticate(cookies.encrypted[COOKIE])
  end

  def current_portal_user = current_portal_session&.portal_user

  # The look of the firm when the person belongs to one company only (and it has one); the neutral look otherwise.
  def portal_brand
    return @portal_brand if defined?(@portal_brand)

    ids = current_portal_user&.open_grants&.distinct&.pluck(:entity_id)
    @portal_brand = ids&.one? ? Portal::Branding.find_by(entity_id: ids.first) : nil
  end

  # Nothing opens without a live session, a second factor configured and a second factor given in this session.
  def require_sign_in!
    return if current_portal_session && current_portal_user.second_factor_configured? && current_portal_session.second_factor_at
    return head(:unauthorized) if request.headers["Accept"].to_s.include?("application/json") # a script is told, not redirected

    redirect_to(if !current_portal_session then portal_sign_in_path
    elsif !current_portal_user.second_factor_configured? then new_portal_second_factor_path
    else portal_second_factor_challenge_path
    end)
  end

  def start_session!(user)
    device, device_cookie, new_device = Portal::Device.recognize(user, cookies.encrypted[DEVICE_COOKIE], ip: request.remote_ip, user_agent: request.user_agent)
    cookies.encrypted[DEVICE_COOKIE] = { value: device_cookie, httponly: true, secure: request.ssl?, same_site: :lax, expires: 1.year.from_now } if device_cookie
    if new_device
      Portal::Event.record!("new_device", user: user, request: request)
      send_security_alert { Portal::SecurityMailer.new_device(user, device).deliver_now } # a security alert: not a preference
    end
    session, token = Portal::Session.start!(user, ip: request.remote_ip, user_agent: request.user_agent, device: device)
    cookies.encrypted[COOKIE] = { value: token, httponly: true, secure: request.ssl?, same_site: :lax }
    @current_portal_session = session
  end

  def end_session!
    current_portal_session&.revoke!
    cookies.delete(COOKIE)
    @current_portal_session = nil
  end

  # A mail that cannot be sent must not stop someone from signing in: the failure is noted.
  def send_security_alert
    yield
  rescue StandardError => e
    Rails.logger.error("portal security alert not sent: #{e.class}")
    Portal::Event.record!("security_alert_not_sent", user: current_portal_user, request: request)
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
