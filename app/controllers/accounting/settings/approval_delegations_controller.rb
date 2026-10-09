# B01a: who stands in for whom, from when to when. The owners' to make, and all the owners see them.
class Accounting::Settings::ApprovalDelegationsController < Accounting::Settings::BaseController
  before_action { require_feature!(:b01a) }
  before_action { authorize Approvals::Delegation }

  def index
    load_screen
  end

  def create
    delegation = Approvals::Delegation.new(delegation_params)
    if delegation.save
      redirect_to accounting_settings_approval_delegations_path, notice: t("approvals.delegation.created")
    else
      redirect_to accounting_settings_approval_delegations_path, alert: delegation.errors.full_messages.to_sentence
    end
  end

  def destroy
    Approvals::Delegation.find(params[:id]).destroy!
    redirect_to accounting_settings_approval_delegations_path, notice: t("approvals.delegation.ended")
  end

  private

  def load_screen
    @delegations = Approvals::Delegation.includes(:delegator, :delegate).order(ends_on: :desc, id: :desc)
    ids = Approvals::Directory.new.approving_ids.to_a
    @members = User.where(id: ids).order(:full_name)
    @policies = Approvals::Policy.active.by_priority
  end

  def delegation_params
    raw = params.require(:delegation).permit(:delegator_id, :delegate_id, :starts_on, :ends_on, :reason, policy_ids: [])
    raw.merge(policy_ids: Array(raw[:policy_ids]).compact_blank.map(&:to_i))
  end
end
