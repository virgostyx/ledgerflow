class Portal::HomeController < Portal::BaseController
  def show
    @companies = Portal::Company.where(id: current_portal_user.grants.in_force.select(:entity_id)).where(active: true).order(:name)
  end
end
