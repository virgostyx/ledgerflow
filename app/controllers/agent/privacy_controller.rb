# What the assistant does with the data of this entity, for everyone who may use it (A04): the class of data and what is done with each, the provider and the models, how long
# conversations are kept, and which version of the terms the owner accepted.
class Agent::PrivacyController < Agent::BaseController
  def show
    @setting = Agent::Setting.for_current_entity
    @consent = Agent::Consent.find_by(version: Agent::Consent::VERSION)
    render layout: !turbo_frame_request?
  end
end
