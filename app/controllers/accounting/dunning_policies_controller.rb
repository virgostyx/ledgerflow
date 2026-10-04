# F09: the rules of the reminders of the entity. The automatic sending of the first level is for the owner alone (`dunning.auto_send`).
class Accounting::DunningPoliciesController < ApplicationController
  before_action { require_feature!(:f09) }
  before_action :set_policy

  def show
    authorize @policy, :show?, policy_class: Accounting::DunningPolicyPolicy
  end

  def update
    authorize @policy, :update?, policy_class: Accounting::DunningPolicyPolicy
    if @policy.update(policy_params)
      redirect_to accounting_dunning_policy_path, notice: t("accounting.dunning.policy_updated")
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_policy = @policy = Accounting::DunningPolicy.for(ActsAsTenant.current_tenant)

  NUMBERS = %i[level_1_days level_2_days level_3_days min_amount follow_up_days min_days_between fee_1 fee_2 fee_3 interest_enabled interest_rate
               indemnity_enabled indemnity_amount from_name reply_to signature].freeze

  def policy_params
    keys = NUMBERS
    keys += [ :auto_send_level_1 ] if Accounting::DunningPolicyPolicy.new(current_user, @policy).auto_send?
    permitted = params.require(:accounting_dunning_policy).permit(*keys, templates: {}).to_h
    permitted["templates"] = merged_templates(permitted["templates"]) if permitted.key?("templates")
    permitted
  end

  # A text left empty, or left as the built-in one, falls back to it: only the texts that were really written are stored.
  def merged_templates(submitted)
    written = submitted.to_h.to_h do |level, languages|
      [ level, languages.to_h.select { |language, text| text.values_at("subject", "body").all?(&:present?) && text.values_at("subject", "body") != Accounting::DunningTexts.built_in(level, language) } ]
    end
    @policy.templates.merge(written).reject { |_, languages| languages.blank? }
  end
end
