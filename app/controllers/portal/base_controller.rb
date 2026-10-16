# B02a: the base of every page of the client portal. It does not inherit from ApplicationController: no Devise, no tenant, nothing of the application.
# What a person from outside sees is what the firm published (Portal::Publication), read through the scope of their grant, never the books.
class Portal::BaseController < ActionController::Base
  layout "portal/application"

  protect_from_forgery with: :exception

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

  private

  def set_security_headers
    response.set_header("Cache-Control", "no-store")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Content-Type-Options", "nosniff")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    response.set_header("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()")
    response.set_header("Cross-Origin-Opener-Policy", "same-origin")
  end
end
