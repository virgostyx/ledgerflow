# A question put to the agent (A01). The answer is not given here: it is written in the background and streamed into the panel, so the model is never called
# from a request.
class Agent::MessagesController < Agent::BaseController
  MAX_LENGTH = 4000

  def create
    @conversation = find_conversation
    @question = params[:question].to_s.strip
    return refuse("This conversation is archived. Start a new one.") if @conversation.archived?
    return refuse("Write a question first.") if @question.blank?
    return refuse("Your question is too long: #{MAX_LENGTH} characters at most. Shorten it, or split it in two.") if @question.length > MAX_LENGTH

    @conversation.update!(title: @question.truncate(60)) if @conversation.title.blank?
    # ponytail: a one second head start, so that the live bubble is on the page before the first piece of text is sent; a reload shows the answer if it is missed.
    Agent::AnswerJob.set(wait: 1.second).perform_later(@conversation, @question, I18n.locale.to_s)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to agent_conversation_path(@conversation), status: :see_other }
    end
  end

  private

  def refuse(message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("agent_conversation_#{@conversation.id}_error", message), status: :unprocessable_entity }
      format.html { redirect_to agent_conversation_path(@conversation), alert: message, status: :see_other }
    end
  end
end
