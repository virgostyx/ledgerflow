# What the agent's defences noticed, for the owners (A03): the events of this entity, newest first, and an alert when there were many in the last day.
class Agent::SecurityEventsController < ApplicationController
  before_action { require_feature!(:agent) }
  before_action { authorize :agent, :configure? }

  def index
    @events = Agent::SecurityEvent.includes(:user).recent.limit(200)
    @alert = Agent::SecurityEvent.signs_of_attack.where(created_at: 1.day.ago..).count > Agent::SecurityEvent::ALERT_THRESHOLD
  end
end
