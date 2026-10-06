# "Useful" or "not useful" on an answer (A01), with what was wrong. One opinion per person and answer: a second one replaces the first.
class Agent::FeedbacksController < Agent::BaseController
  def create
    message = find_conversation.messages.assistant.find(params[:message_id])
    feedback = Agent::Feedback.find_or_initialize_by(message: message, user: current_user)
    feedback.assign_attributes(rating: params[:rating], category: params[:category].presence, comment: params[:comment].presence)

    if feedback.save
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.update("agent_message_#{message.id}_feedback", partial: "agent/messages/thanks") }
        format.any { head :no_content }
      end
    else
      head :unprocessable_entity
    end
  rescue ArgumentError # a rating the enum does not know
    head :unprocessable_entity
  end
end
