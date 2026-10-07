# "Useful" or "not useful" on an answer, through the API (A01): one opinion per person and answer, the last one counts.
class Api::V1::Public::AgentFeedbackController < Api::V1::Public::AgentBaseController
  self.action_scopes = { create: "agent:use" }

  def create
    message = conversations.find(params[:id]).messages.assistant.find(params[:message_id])
    feedback = Agent::Feedback.find_or_initialize_by(message: message, user: @api_client.owner)
    feedback.assign_attributes(rating: params[:rating], category: params[:category].presence, comment: params[:comment].presence)
    return unprocessable(feedback.errors.full_messages.to_sentence) unless feedback.save

    render json: { data: { message_id: message.id, rating: feedback.rating, category: feedback.category } }, status: :created
  rescue ArgumentError # a rating the enum does not know
    unprocessable("rating must be useful or not_useful")
  end
end
