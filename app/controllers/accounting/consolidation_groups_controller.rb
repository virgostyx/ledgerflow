# F12b: the groups to consolidate, seen from their parent company: who is in the group (with the percentage held and its history), the mappings of headings, and the
# recorded validations by an accountant of each rule (a rule without one is not applied). All of it needs access to every member company, or nothing is shown.
class Accounting::ConsolidationGroupsController < ApplicationController
  before_action { require_feature!(:f12) }
  before_action :set_group, except: %i[index new create]
  before_action :require_every_member, except: %i[index new create]

  def index
    authorize :consolidation, :index?, policy_class: Accounting::ConsolidationPolicy
    @groups = Consolidation::Group.order(:name)
  end

  def new
    authorize :consolidation, :create?, policy_class: Accounting::ConsolidationPolicy
  end

  def create
    authorize :consolidation, :create?, policy_class: Accounting::ConsolidationPolicy
    group = Consolidation::Group.new(name: params[:name].to_s.strip, currency: params[:currency].presence || "EUR")
    saved = Consolidation::Group.transaction do
      group.save && group.members.create!(member_entity: ActsAsTenant.current_tenant).stakes.create!(percentage: 100, effective_on: Date.new(2000, 1, 1))
    end
    saved ? redirect_to(accounting_consolidation_group_path(group), notice: "Group created: this company is in it at 100 %.") : redirect_to(new_accounting_consolidation_group_path, alert: group.errors.full_messages.to_sentence)
  end

  def show
    authorize :consolidation, :show?, policy_class: Accounting::ConsolidationPolicy
    @members = @group.members.includes(:member_entity, :stakes).order(:id)
    @runs = @group.runs.order(id: :desc)
    @addable = current_user.current_entities.active.where("entities.features @> ?", { "f12" => true }.to_json).where.not(id: @members.map(&:member_entity_id)).order(:name)
    @validations = @group.rule_validations.order(:id)
    @mappings = @group.mappings.includes(:member).order(:id)
    @rules = Consolidation::Rules::DEFINITIONS
  end

  def add_member
    authorize :consolidation, :update?, policy_class: Accounting::ConsolidationPolicy
    entity = current_user.current_entities.active.find(params[:entity_id])
    member = @group.members.build(member_entity: entity, method: params[:method].presence || "full", currency: params[:currency].presence || @group.currency,
                                  joined_on: params[:joined_on].presence, left_on: params[:left_on].presence)
    if member.save
      member.stakes.create!(percentage: params[:percentage], effective_on: params[:effective_on].presence || Date.new(2000, 1, 1))
      redirect_to accounting_consolidation_group_path(@group), notice: "#{entity.name} added."
    else
      redirect_to accounting_consolidation_group_path(@group), alert: member.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordInvalid => e
    member.destroy
    redirect_to accounting_consolidation_group_path(@group), alert: e.message
  end

  def remove_member
    authorize :consolidation, :update?, policy_class: Accounting::ConsolidationPolicy
    member = @group.members.find(params[:member_id])
    return redirect_to(accounting_consolidation_group_path(@group), alert: "The parent company stays in its group.") if member.parent?
    return redirect_to(accounting_consolidation_group_path(@group), alert: "A frozen run names this member: it stays (set its date of leaving instead).") if @group.runs.where(status: "frozen").exists?

    member.destroy
    redirect_to accounting_consolidation_group_path(@group), notice: "Removed."
  end

  def add_stake
    authorize :consolidation, :update?, policy_class: Accounting::ConsolidationPolicy
    stake = @group.members.find(params[:member_id]).stakes.build(percentage: params[:percentage], effective_on: params[:effective_on])
    stake.save ? redirect_to(accounting_consolidation_group_path(@group), notice: "Percentage recorded, from #{stake.effective_on}.") : redirect_to(accounting_consolidation_group_path(@group), alert: stake.errors.full_messages.to_sentence)
  end

  def add_mapping
    authorize :consolidation, :update?, policy_class: Accounting::ConsolidationPolicy
    mapping = @group.mappings.build(params.permit(:consolidation_member_id, :statement, :source_code, :consolidated_code))
    mapping.save ? redirect_to(accounting_consolidation_group_path(@group), notice: "Mapping saved.") : redirect_to(accounting_consolidation_group_path(@group), alert: mapping.errors.full_messages.to_sentence)
  end

  def remove_mapping
    authorize :consolidation, :update?, policy_class: Accounting::ConsolidationPolicy
    @group.mappings.find(params[:mapping_id]).destroy
    redirect_to accounting_consolidation_group_path(@group), notice: "Mapping removed."
  end

  # An accountant's validation of a rule: the owner records who validated, in what capacity, where it is written, and the parameters. Only then is the rule applied.
  def add_validation
    authorize :consolidation, :approve?, policy_class: Accounting::ConsolidationPolicy
    parameters = JSON.parse(params[:parameters].presence || "{}")
    validation = @group.rule_validations.build(params.permit(:rule_key, :validated_by_name, :validated_by_title, :validated_on, :reference, :note).merge(parameters: parameters, recorded_by: current_user))
    return redirect_to(accounting_consolidation_group_path(@group), alert: "The rule already has a validation in force: revoke it first.") if validation.rule_key.present? && @group.validation_for(validation.rule_key)

    if validation.save
      Accounting::AuditLog.record!(auditable: @group, action: "consolidation_rule_validated", user: current_user, payload: { rule: validation.rule_key, by: validation.validated_by_name, reference: validation.reference, parameters: parameters })
      redirect_to accounting_consolidation_group_path(@group), notice: "Validation recorded: the rule is applied from the next calculation."
    else
      redirect_to accounting_consolidation_group_path(@group), alert: validation.errors.full_messages.to_sentence
    end
  rescue JSON::ParserError
    redirect_to accounting_consolidation_group_path(@group), alert: "The parameters are not valid JSON."
  end

  def revoke_validation
    authorize :consolidation, :approve?, policy_class: Accounting::ConsolidationPolicy
    validation = @group.rule_validations.find(params[:validation_id])
    validation.revoke!
    Accounting::AuditLog.record!(auditable: @group, action: "consolidation_rule_revoked", user: current_user, payload: { rule: validation.rule_key })
    redirect_to accounting_consolidation_group_path(@group), notice: "Validation revoked: the rule is no longer applied."
  end

  private

  def set_group = @group = Consolidation::Group.find(params[:id])

  # Everything about a group needs the whole group: not one company less.
  def require_every_member
    missing = Consolidation::Access.missing(current_user, @group)
    redirect_to accounting_consolidation_groups_path, alert: "You do not have access to every company of this group (#{missing} missing): a consolidation is refused whole, never partial." if missing.positive?
  end
end
