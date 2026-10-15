# B03c: the public page of a certificate of integrity, for anyone who has its address (an unguessable identifier, a few requests a minute per address). It says whether the
# signature is genuine, when and at which level it was issued, the fingerprints, and what was validated since: no amount, no name of a person, and the name of the company only if
# its owner allows it.
class VerificationsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_second_factor!
  skip_before_action :set_current_entity
  skip_before_action :require_entity!
  layout "devise"

  def show
    @certificate = IntegrityCertificate.unscoped.find_by(uuid: params[:uuid].to_s) or return head(:not_found)
    @entity = @certificate.entity
    return head(:not_found) unless @entity.feature?(:b03c)

    @document = @certificate.payload_hash
    @verification = Integrity::VerifyCertificate.call(@certificate)
    @show_company = @entity.integrity_public_company_name
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end
end
