# B02c: what the firm does about the client's dashboard: generate a snapshot, let it through, write the word of the accountant (and approve it), set the alert on the forecast cash.
class Accounting::PortalDashboardController < ApplicationController
  before_action -> { require_feature!(:b02c) }
  before_action -> { authorize Accounting::PortalAccessPolicy, :index?, policy_class: Accounting::PortalAccessPolicy }
  before_action :set_snapshot, only: %i[publish word approve_word]

  def index
    @snapshots = Portal::Snapshot.where(entity_id: entity.id).order(generated_at: :desc).limit(30)
    @rules = Portal::AlertRule.where(entity_id: entity.id).order(:id)
  end

  def generate
    result = PortalAdmin::GenerateSnapshot.call(entity: entity)
    redirect_to accounting_portal_dashboard_index_path, **(result.success? ? { notice: "Snapshot made." } : { alert: result.message })
  end

  def publish
    PortalAdmin::ReviewSnapshot.publish(@snapshot, by: current_user)
    redirect_to accounting_portal_dashboard_index_path, notice: "Published."
  end

  def word
    PortalAdmin::ReviewSnapshot.write_word(@snapshot, text: params[:text], source: PortalAdmin::ReviewSnapshot::SOURCES.include?(params[:source]) ? params[:source] : "human", by: current_user)
    redirect_to accounting_portal_dashboard_index_path, notice: "Saved. It is shown to the client once approved."
  end

  def approve_word
    PortalAdmin::ReviewSnapshot.approve_word(@snapshot, by: current_user)
    redirect_to accounting_portal_dashboard_index_path, notice: "Approved."
  end

  def alert_rules
    threshold = BigDecimal(params[:threshold].to_s.tr(",", "."), exception: false)
    return redirect_to(accounting_portal_dashboard_index_path, alert: "Give the threshold as a number.") unless threshold&.finite?

    Portal::AlertRule.create!(entity_id: entity.id, kind: "cash_below", threshold: threshold)
    redirect_to accounting_portal_dashboard_index_path, notice: "Alert set."
  end

  def alert_rule
    Portal::AlertRule.where(entity_id: entity.id).find(params[:rule]).update!(active: false)
    redirect_to accounting_portal_dashboard_index_path, notice: "Alert turned off."
  end

  def settings
    required = params[:snapshot_approval_required] == "1"
    entity.update!(snapshot_approval_required: required) if entity.snapshot_approval_required? != required
    redirect_to accounting_portal_dashboard_index_path, notice: "Saved."
  end

  private

  def entity = ActsAsTenant.current_tenant
  def set_snapshot = @snapshot = Portal::Snapshot.where(entity_id: entity.id).find(params[:id])
end
