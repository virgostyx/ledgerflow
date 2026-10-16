# B02b: what makes the portal installable and usable offline, public (it holds nothing of anyone): the manifest, and the service worker, which is the outbox and its own lines
# served as one file from the root so that its scope is the whole portal.
class Portal::ServiceWorkerController < Portal::BaseController
  skip_before_action :require_sign_in!
  skip_forgery_protection only: :worker # a script served to a GET, which is what a service worker is: it holds nothing of anyone

  SCRIPTS = %w[portal_outbox.js portal_service_worker.js].freeze

  def manifest
    render json: { name: "Client portal", short_name: "Portal", start_url: "/", scope: "/", display: "standalone", background_color: "#ffffff", theme_color: "#111827",
                   icons: [ { src: "/icon.png", sizes: "512x512", type: "image/png" } ] }, content_type: "application/manifest+json"
  end

  def worker
    response.set_header("Service-Worker-Allowed", "/")
    render plain: SCRIPTS.map { |name| Rails.root.join("app/assets/javascripts", name).read }.join("\n"), content_type: "text/javascript"
  end
end
