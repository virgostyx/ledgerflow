# B01a: "To approve". The invoices waiting for my approval, one to decide on, and bulk approval of the small ones.
# What I may decide on is the circuit's business (Approvals::Approvers); the screen only shows it and relays the decision, with the
# fingerprint of the content that was on screen.
class Accounting::ApprovalsController < ApplicationController
  before_action { require_feature!(:b01a) }

  def index
    authorize Approvals::Request
    @rows = Approvals::Inbox.for(current_user, params.permit(:supplier, :min_amount, :max_amount, :project_id))
    @bulk = ActsAsTenant.current_tenant.bulk_threshold
  end

  def show
    @request = Approvals::Request.find(params[:id])
    authorize @request
    @invoice = @request.subject
    @history = Approvals::SupplierHistory.for(@invoice)
    @can_decide = @request.pending? && Approvals::Approvers.for(@request).key?(current_user.id)
    @total = @invoice.lines.sum(:total_incl_vat)
  end

  def decide
    request = Approvals::Request.find(params[:id])
    authorize request
    result = Approvals::Decide.call(request: request, user: current_user, decision: params[:decision].to_s, comment: params[:comment].presence,
                                    content_fingerprint: params[:content_fingerprint].to_s, channel: :web, device_fingerprint: device_fingerprint)
    if result.success?
      redirect_to accounting_approvals_path, notice: t("approvals.decided.#{params[:decision]}")
    else
      # a request that is no longer waiting (decided, or invalidated because the invoice changed) has nothing to show but its place in the list
      redirect_to request.reload.pending? ? accounting_approval_path(request) : accounting_approvals_path, alert: result.message
    end
  end

  # Each invoice is decided on its own (one decision, one audit entry each); what is over the threshold or carries a warning is left.
  def bulk
    authorize Approvals::Request, :bulk?
    threshold = ActsAsTenant.current_tenant.bulk_threshold
    return redirect_to(accounting_approvals_path, alert: t("approvals.errors.bulk_off")) unless threshold

    rows = Approvals::Inbox.for(current_user).index_by { |row| row.request.id.to_s }
    done = Array(params[:request_ids]).count do |id|
      row = rows[id.to_s]
      next false unless row && row.amount <= threshold && row.warnings.empty?

      Approvals::Decide.call(request: row.request, user: current_user, decision: "approved", channel: :web, device_fingerprint: device_fingerprint,
                             content_fingerprint: params.dig(:fingerprints, id).to_s).success?
    end
    left = Array(params[:request_ids]).size - done
    flash[:notice] = t("approvals.bulk.approved", count: done) if done.positive?
    flash[:alert] = t("approvals.bulk.left", count: left) if left.positive?
    redirect_to accounting_approvals_path
  end

  private

  # What the circuit keeps of the device: a short digest of the browser, never the browser itself.
  def device_fingerprint = Digest::SHA256.hexdigest(request.user_agent.to_s)[0, 16]
end
