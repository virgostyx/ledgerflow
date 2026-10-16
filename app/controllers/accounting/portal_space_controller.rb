# B02c: the portal at a glance, for the firm: what the clients sent lately, what waits for them (questions by age), the publications and where their approvals stand, the activity, who does not come.
class Accounting::PortalSpaceController < ApplicationController
  before_action -> { authorize Accounting::PortalAccessPolicy, :index?, policy_class: Accounting::PortalAccessPolicy }

  def show
    @documents = Accounting::Document.portal.order(created_at: :desc).limit(10)
    @questions = Portal::Question.where(entity_id: entity.id).open.order(:asked_at).limit(20)
    @publications = Portal::Publication.where(entity_id: entity.id).visible.includes(:approver_rows, approvals: :portal_user).order(published_at: :desc).limit(10)
    @statuses = @publications.index_with { |publication| PortalAdmin::ApprovalStatus.call(publication) }
    @events = Portal::Event.where(entity_id: entity.id).order(id: :desc).includes(:portal_user).limit(10)
    @indicators = PortalAdmin::SpaceIndicators.call(entity: entity)
  end

  private

  def entity = ActsAsTenant.current_tenant
end
