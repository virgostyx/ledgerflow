# The owner's settings of the agent for the entity (A01, A04): on or off, the acceptance of the data processing terms, how long conversations are kept, and what goes to the
# language model class of data by class of data. Open even while the agent is off, since this is where it is turned on; closed while the feature of the entity is off.
class Agent::SettingsController < ApplicationController
  before_action { require_feature!(:agent) }
  before_action { authorize :agent, :configure? }
  before_action :set_setting

  def show; end

  def update
    @setting.assign_attributes(setting_params)
    if @setting.enabled? && !Agent::Consent.current? && params[:accept_consent] != "1"
      @setting.errors.add(:base, "Accept the data processing terms to turn the assistant on.")
      return render :show, status: :unprocessable_entity
    end

    Agent::Setting.transaction do
      Agent::Consent.accept!(current_user) if params[:accept_consent] == "1"
      @setting.save!
    end
    redirect_to agent_setting_path, notice: "Assistant settings saved.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    render :show, status: :unprocessable_entity
  end

  private

  def set_setting = @setting = Agent::Setting.for_current_entity

  # A mode left blank goes back to the default of its class.
  def setting_params
    permitted = params.require(:agent_setting).permit(:enabled, :retention_days, :restricted, :review_threshold, data_class_modes: Agent::Setting::DATA_CLASSES)
    modes = permitted.delete(:data_class_modes)
    permitted[:data_class_modes] = modes.to_h.compact_blank if modes
    permitted
  end
end
