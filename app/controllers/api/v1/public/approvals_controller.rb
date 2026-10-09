# B01a: the approvals through the API (scopes approvals:read and approvals:decide, both within the rights of the owner of the token). The same circuit as the
# screens - Approvals::Inbox, Approvals::Decide - so that the fingerprint of the content seen, the separation of tasks and the audit trail are the same;
# the decision is recorded from the api channel. A request the owner cannot decide and never decided is not found.
class Api::V1::Public::ApprovalsController < Api::V1::Public::BaseController
  SORTS = { "id" => "approval_requests.id", "created_at" => "approval_requests.created_at" }.freeze
  FILTERS = {
    "supplier" => ->(scope, value) {
      suppliers = Accounting::Invoice.joins(:partner).where("accounting_partners.name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(value)}%").select(:id)
      scope.where(subject_type: "Accounting::Invoice", subject_id: suppliers)
    }
  }.freeze
  # What a refusal of the circuit becomes: [status, title, slug].
  REFUSALS = {
    feature_off: [ :forbidden, "Approvals are not enabled", "approvals-not-enabled" ],
    not_an_approver: [ :forbidden, "Not an approver", "not-an-approver" ],
    own_entry: [ :forbidden, "Separation of duties", "separation-of-duties" ],
    content_changed: [ :conflict, "The invoice changed", "content-changed" ],
    not_pending: [ :conflict, "Already decided", "already-decided" ],
    already_decided: [ :conflict, "Already decided", "already-decided" ],
    step_up_required: [ :forbidden, "A second factor is needed", "step-up-required" ],
    invalid_transfer: [ :unprocessable_content, "Invalid hand-over", "invalid-transfer" ],
    reason_required: [ :unprocessable_content, "A reason is required", "reason-required" ],
    unknown_decision: [ :unprocessable_content, "Unknown decision", "unknown-decision" ]
  }.freeze

  self.action_scopes = { index: "approvals:read", show: "approvals:read", decision: "approvals:decide" }

  before_action :require_approvals!

  def index
    ids = Approvals::Inbox.for(owner).map { |row| row.request.id }
    page = paginate(Approvals::Request.where(id: ids).includes(:policy, subject: :partner), sorts: SORTS, filters: FILTERS, default_sort: "created_at")
    return if performed?

    render json: { data: page[:rows].map { |request| serialize(request, detail: false) }, meta: page[:meta] }
  end

  def show
    render_request(find_request)
  end

  def decision
    request = find_request
    return problem(:forbidden, "Forbidden", detail: "Your account may not decide on approvals.", slug: "forbidden") unless Approvals::RequestPolicy.new(owner, request).decide?

    idempotently do
      result = Approvals::Decide.call(request: request, user: owner, decision: params[:decision].to_s, comment: params[:comment].presence,
                                      content_fingerprint: params[:content_fingerprint].to_s, channel: :api, device_fingerprint: "token-#{@api_client.id}", transfer_to_id: params[:transfer_to_id].presence&.to_i)
      next refuse(result) if result.failure?

      render_request(request.reload)
    end
  end

  private

  def owner = @api_client.owner

  def require_approvals!
    problem(:forbidden, "Approvals are not enabled", detail: "Invoice approval is not turned on for this entity.", slug: "approvals-not-enabled") unless ActsAsTenant.current_tenant.feature?(:b01a)
  end

  # Found when it waits for the owner, or when the owner decided on it: nothing else is told to this token.
  def find_request
    request = Approvals::Request.includes(:policy, decisions: %i[approver on_behalf_of transferred_to], subject: :partner).find(params[:id])
    raise ActiveRecord::RecordNotFound unless Approvals::Approvers.for(request).key?(owner.id) || request.decisions.any? { |d| d.approver_id == owner.id }

    request
  end

  def refuse(result)
    status, title, slug = REFUSALS.fetch(result[:code])
    problem(status, title, detail: result.message, slug: slug)
  end

  def render_request(request)
    response.set_header("ETag", etag_for("approval", request.id, request.status, request.current_step, request.content_fingerprint, request.decisions.size))
    render json: { data: serialize(request, detail: true) }
  end

  def serialize(request, detail:)
    invoice = request.subject
    amount = Accounting::InvoiceLine.unscope(:order).where(invoice_id: invoice.id).sum(:total_incl_vat) # the database adds up
    data = { id: request.id, status: request.status, level: request.current_step, content_fingerprint: request.content_fingerprint,
             submitted_at: request.submitted_at&.iso8601, created_at: request.created_at.iso8601,
             invoice: { id: invoice.id, number: invoice.invoice_number, supplier: invoice.partner.name, invoice_date: invoice.invoice_date.iso8601, due_date: invoice.due_date&.iso8601,
                        currency: invoice.currency, amount_incl_vat: money(amount), amount_eur: money(Fx::Convert.to_eur(amount, invoice.exchange_rate)) } }
    return data unless detail

    data.merge(can_decide: request.pending? && Approvals::Approvers.for(request).key?(owner.id), warnings: Approvals::SupplierHistory.for(invoice).warnings.map(&:to_s),
               invoice: data[:invoice].merge(lines: invoice.lines.includes(:account).map { |l| { account: l.account.code, description: l.description, amount_incl_vat: money(l.total_incl_vat) } }),
               levels: levels(request))
  end

  def levels(request)
    request.policy.steps.map do |step|
      { position: step.position, mode: step.mode, current: request.pending? && step.position == request.current_step,
        decisions: request.decisions.select { |d| d.step_position == step.position }.map { |d| decision_json(d) } }
    end
  end

  def decision_json(decision)
    { decision: decision.decision, approver: decision.approver.full_name, on_behalf_of: decision.on_behalf_of&.full_name, transferred_to: decision.transferred_to&.full_name, comment: decision.comment,
      channel: decision.channel, decided_at: decision.decided_at.iso8601 }
  end

  def money(value) = format("%.2f", value)
end
