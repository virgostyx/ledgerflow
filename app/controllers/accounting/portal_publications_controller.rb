# B02a: what the firm publishes to the client portal of the company: the list, a new publication (or a new version of one), the withdrawal.
class Accounting::PortalPublicationsController < ApplicationController
  before_action -> { require_feature!(:b02a) }
  before_action -> { authorize Accounting::PortalAccessPolicy, "#{action_name}?".to_sym, policy_class: Accounting::PortalAccessPolicy }

  def index
    @publications = Portal::Publication.where(entity_id: entity.id).includes(:files).order(published_at: :desc).limit(100)
    @people = people
  end

  def create
    uploads = Array(params[:files]).select { |f| f.respond_to?(:tempfile) }
    files = uploads.map { |f| { filename: f.original_filename, content_type: f.content_type, data: f.read } }
    replaces = Portal::Publication.where(entity_id: entity.id).find_by(token: params[:replaces]) if params[:replaces].present?
    result = PortalAdmin::Publish.call(
      entity: entity, kind: params[:kind], title: params[:title], message: params[:message], files: files, replaces: replaces, by: current_user,
      recipients: people.where(id: Array(params[:recipient_ids])).to_a, requires_approval: params[:requires_approval] == "1", watermark: params[:watermark] != "0",
      expires_at: params[:expires_at].presence
    )
    if result.success?
      redirect_to accounting_portal_publications_path, notice: "Published."
    else
      redirect_to accounting_portal_publications_path, alert: result.message
    end
  end

  def withdraw
    publication = Portal::Publication.where(entity_id: entity.id).find_by!(token: params[:token])
    PortalAdmin::Withdraw.call(publication: publication, by: current_user, reason: params[:reason].to_s.strip.presence || "withdrawn")
    redirect_to accounting_portal_publications_path, notice: "Withdrawn."
  end

  private

  def entity = ActsAsTenant.current_tenant

  # The people of this company, to address a publication to some of them only.
  def people = PortalUser.where(id: Portal::Grant.in_force.where(entity_id: entity.id).select(:portal_user_id))
end
