# When and how a person wants their summary (A10a): their own preference for this entity, off until they turn it on.
class Agent::DigestPreferencesController < Agent::BaseController
  def show = @preference = Agent::DigestPreference.for(current_user)

  def update
    @preference = Agent::DigestPreference.for(current_user)
    @preference.assign_attributes(params.require(:agent_digest_preference).permit(:enabled, :frequency, :weekday, :send_hour, :time_zone, :email).merge(sections: Array(params.dig(:agent_digest_preference, :sections)) & Agent::Digest::Sources::SECTIONS.keys))
    if @preference.save
      redirect_to agent_digests_path, notice: "Summary preferences saved.", status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  end
end
