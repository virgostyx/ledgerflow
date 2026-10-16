# B02b: the firm asks the clients of the company for the supporting documents of bank lines (those still pending and without a document), follows what came back, and chooses whether the
# clients see bank lines at all.
class Accounting::PortalDocumentRequestsController < ApplicationController
  before_action -> { require_feature!(:b02b) }
  before_action -> { authorize Accounting::PortalAccessPolicy, "#{action_name == 'settings' ? 'branding' : action_name}?".to_sym, policy_class: Accounting::PortalAccessPolicy }

  def index
    taken = Accounting::DocumentLink.where(target_type: "Accounting::BankTransaction").select(:target_id)
    asked = Portal::DocumentRequestLine.open_ones.where(entity_id: entity.id).select(:bank_transaction_id)
    @candidates = Accounting::BankTransaction.pending.where.not(id: taken).where.not(id: asked).order(transaction_date: :desc).limit(200)
    @indicators = PortalAdmin::UploadIndicators.call(entity: entity)
    @lines = Portal::DocumentRequestLine.where(entity_id: entity.id).includes(:request).order(id: :desc).limit(200)
  end

  def create
    lines = Accounting::BankTransaction.where(id: Array(params[:line_ids])).to_a
    result = PortalAdmin::RequestDocuments.call(entity: entity, lines: lines, message: params[:message], due_on: params[:due_on], by: current_user)
    if result.success?
      redirect_to accounting_portal_document_requests_path, notice: "Asked. The clients who may see bank lines are told."
    else
      redirect_to accounting_portal_document_requests_path, alert: result.message
    end
  end

  def settings
    show = params[:show_bank_lines] == "1"
    if entity.portal_show_bank_lines? != show
      entity.update!(portal_show_bank_lines: show)
      Accounting::AuditLog.record!(auditable: entity, action: "portal_bank_lines_visibility_changed", user: current_user, payload: { show_bank_lines: show })
    end
    redirect_to accounting_portal_document_requests_path, notice: "Saved."
  end

  private

  def entity = ActsAsTenant.current_tenant
end
