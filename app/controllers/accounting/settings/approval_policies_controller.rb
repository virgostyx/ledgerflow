# B01a: the approval policies (who must approve which purchase invoices, level by level). The owner's, and closed while the feature is off.
class Accounting::Settings::ApprovalPoliciesController < Accounting::Settings::BaseController
  before_action { require_feature!(:b01a) }
  before_action { authorize Approvals::Policy }
  before_action :set_policy, only: %i[edit update]

  def index
    @active  = Approvals::Policy.active.by_priority.includes(steps: :escalate_to)
    @retired = Approvals::Policy.where(active: false).order(updated_at: :desc).includes(steps: :escalate_to)
  end

  def new
    @policy = Approvals::Policy.new(priority: 100, reminder_hours: [ 24, 48 ])
    load_members
  end

  def create
    result = Approvals::SavePolicy.call(policy: nil, attributes: policy_attributes, steps: step_attributes)
    return redirect_to(accounting_settings_approval_policies_path, notice: t("approvals.policy.created")) if result.success?

    retry_form(Approvals::Policy.new(policy_attributes.slice(:name, :priority, :active)), result.message, :new)
  end

  def edit
    load_members
  end

  def update
    result = Approvals::SavePolicy.call(policy: @policy, attributes: policy_attributes, steps: step_attributes)
    if result.success?
      notice = result[:policy] == @policy ? t("approvals.policy.updated") : t("approvals.policy.revised", version: result[:policy].version)
      redirect_to accounting_settings_approval_policies_path, notice: notice
    else
      retry_form(@policy, result.message, :edit)
    end
  end

  private

  def set_policy = (@policy = Approvals::Policy.find(params[:id]))

  def load_members
    ids = Approvals::Directory.new.approving_ids.to_a
    @members = User.where(id: ids).order(:full_name)
  end

  def policy_attributes
    raw = params.require(:policy).permit(:name, :priority, :active, :reminder_hours, conditions: [ :min_amount, :max_amount, :partner_ids, :account_ids, :project_ids, :currencies, :first_payment, { document_types: [] } ])
    raw.to_h.symbolize_keys.merge(reminder_hours: raw[:reminder_hours].to_s.split(",").map(&:strip))
  end

  # Levels come as steps[0], steps[1]... in the order of the form.
  def step_attributes
    submitted = params[:steps].respond_to?(:to_unsafe_h) ? params[:steps].to_unsafe_h : {}
    submitted.sort_by { |index, _| index.to_i }.map { |_, step| step.slice("mode", "approver_user_ids", "approver_roles", "service_hours", "escalate_to_id") }
  end

  def retry_form(policy, message, template)
    @policy = policy
    @typed_steps = step_attributes
    load_members
    flash.now[:alert] = message
    render template, status: :unprocessable_content
  end
end
