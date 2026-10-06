# The Stop button (A01): writes the request; the runner reads it between two steps, so that nothing runs after it.
class Agent::StopsController < Agent::BaseController
  def create
    find_conversation.request_stop!
    head :no_content
  end
end
