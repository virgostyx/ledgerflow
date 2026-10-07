# "Useful" or "not useful" on an answer (A01), with what was wrong. One opinion per person and answer: a second one replaces the first.
class Agent::FeedbacksController < Agent::BaseController
  def create
    message = find_conversation.messages.assistant.find(params[:message_id])
    feedback = Agent::Feedback.find_or_initialize_by(message: message, user: current_user)
    feedback.assign_attributes(rating: params[:rating], category: params[:category].presence, comment: params[:comment].presence)

    if feedback.save
      note_knowledge_gap(message) if feedback.not_useful?
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

  private

  # An answer that rested on the knowledge base and was not useful says what the base lacks (A06).
  def note_knowledge_gap(message)
    return unless message.tool_calls.exists?(tool: "search_knowledge")

    question = message.conversation.messages.where(role: "user").where(id: ...message.id).order(:id).last&.content
    Knowledge::Gap.record(kind: "not_useful", question: question, user: current_user, message: message) if question.present?
  end
end
