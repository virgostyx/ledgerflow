# B02a: what the firm publishes to the client portal of the company: the list, a new publication (or a new version of one), the withdrawal.
class Accounting::PortalPublicationsController < ApplicationController
  before_action -> { require_feature!(:b02a) }
  before_action -> { authorize Accounting::PortalAccessPolicy, "#{action_name}?".to_sym, policy_class: Accounting::PortalAccessPolicy }

  def index
    @publications = Portal::Publication.where(entity_id: entity.id).includes(:files, :approver_rows, approvals: :portal_user).order(published_at: :desc).limit(100)
    @statuses = @publications.index_with { |publication| PortalAdmin::ApprovalStatus.call(publication) }
    @people = people
  end

  def create
    uploads = Array(params[:files]).select { |f| f.respond_to?(:tempfile) }
    files = uploads.map { |f| { filename: f.original_filename, content_type: f.content_type, data: f.read } }
    replaces = Portal::Publication.where(entity_id: entity.id).find_by(token: params[:replaces]) if params[:replaces].present?
    result = PortalAdmin::Publish.call(
      entity: entity, kind: params[:kind], title: params[:title], message: params[:message], files: files, replaces: replaces, by: current_user,
      recipients: people.where(id: Array(params[:recipient_ids])).to_a, requires_approval: params[:requires_approval] == "1", watermark: params[:watermark] != "0",
      expires_at: params[:expires_at].presence, approvers: people.where(id: Array(params[:approver_ids])).to_a, approvals_required: params[:approvals_required].presence || "one"
    )
    if result.success?
      redirect_to accounting_portal_publications_path, notice: "Published."
    else
      redirect_to accounting_portal_publications_path, alert: result.message
    end
  end

  # B02c: the proof of an approval, as a document (the PDF), and the check of the proof.
  def proof
    approval = Portal::Approval.where(entity_id: entity.id).find(params[:approval_id])
    send_data PortalAdmin::ApprovalProofPdf.call(approval), filename: "proof-of-approval-#{approval.id}.pdf", type: "application/pdf", disposition: "attachment"
  end

  def settings
    required = params[:client_approval_required] == "1"
    if entity.client_approval_required? != required
      entity.update!(client_approval_required: required)
      Accounting::AuditLog.record!(auditable: entity, action: "client_approval_required_changed", user: current_user, payload: { required: required })
    end
    redirect_to accounting_portal_publications_path, notice: "Saved."
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
