# B02a: "Portal activity": sign-ins, readings, downloads, deposits and answers of the people from outside, by person, and what looks unusual.
class Accounting::PortalActivityController < ApplicationController
  before_action -> { require_feature!(:b02a) }
  before_action -> { authorize Accounting::PortalAccessPolicy, :index?, policy_class: Accounting::PortalAccessPolicy }

  def index
    entity = ActsAsTenant.current_tenant
    events = PortalAdmin::ActivityFeed.call(entity: entity)
    events = events.where(portal_user_id: params[:person_id]) if params[:person_id].present?
    @events = events.includes(:portal_user).order(occurred_at: :desc).limit(200)
    @unusual = PortalAdmin::UnusualActivity.call(entity: entity)
    @people = PortalUser.where(id: Portal::Grant.where(entity_id: entity.id).select(:portal_user_id)).order(:full_name)
  end
end
