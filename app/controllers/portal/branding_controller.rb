# The look of the firm, served from the portal's own host: a stylesheet made of validated colours only, and the logo with a type the browser may not guess.
class Portal::BrandingController < Portal::BaseController
  skip_before_action :require_sign_in!, only: :stylesheet # the sign-in pages use it too: neutral colours when nobody is signed in
  skip_forgery_protection

  def stylesheet
    brand = portal_brand
    primary = brand&.primary_color || "#1f2937"
    background = brand&.background_color || "#f9fafb"
    render plain: <<~CSS, content_type: "text/css"
      body { background: #{background}; }
      .portal-button { background: #{primary}; color: #{Portal::Branding::BUTTON_TEXT}; }
    CSS
  end

  def logo
    return head(:not_found) unless portal_brand&.logo?

    send_data portal_brand.logo, type: portal_brand.logo_content_type, disposition: "inline"
  end
end
