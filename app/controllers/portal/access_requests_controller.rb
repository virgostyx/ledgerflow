# A director asks the firm to give someone access; nobody from outside invites anyone.
class Portal::AccessRequestsController < Portal::BaseController
  def new
    @companies = askable_companies
  end

  def create
    company = askable_companies.find_by(id: params[:company])
    return not_in_scope(params[:company]) unless company

    request_record = Portal::AccessRequest.new(entity_id: company.id, requested_by: current_portal_user, token: SecureRandom.urlsafe_base64(12),
                                               email: params[:email].to_s.strip, full_name: params[:full_name].to_s.strip, role: params[:role].to_s, note: params[:note].to_s.strip.first(500))
    if request_record.save
      record_event("access_requested", entity_id: company.id, target_token: request_record.token)
      redirect_to portal_root_path, notice: "Your request was sent to your accountant. Nothing happens until they decide."
    else
      @companies = askable_companies
      flash.now[:alert] = request_record.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  private

  def askable_companies
    Portal::Company.where(id: current_portal_user.open_grants.where("portal_grants.capabilities @> ?", [ "access.request" ].to_json).select(:entity_id)).order(:name)
  end
end
