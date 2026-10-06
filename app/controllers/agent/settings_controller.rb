# The owner's settings of the agent for the entity (A01): on or off, and how long conversations are kept. The consent of A04 will stand in front of "on".
# Open even while the agent is off, since this is where it is turned on; closed while the feature of the entity is off.
class Agent::SettingsController < ApplicationController
  before_action { require_feature!(:agent) }
  before_action { authorize :agent, :configure? }
  before_action :set_setting

  def show; end

  def update
    if @setting.update(setting_params)
      redirect_to agent_setting_path, notice: "Assistant settings saved.", status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_setting = @setting = Agent::Setting.for_current_entity

  def setting_params = params.require(:agent_setting).permit(:enabled, :retention_days)
end
