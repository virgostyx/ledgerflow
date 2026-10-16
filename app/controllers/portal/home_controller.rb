class Portal::HomeController < Portal::BaseController
  def show
    @companies = Portal::Company.where(id: current_portal_user.open_grants.select(:entity_id)).order(:name)
  end
end
