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

    review = Agent::SensitiveInput.review(@question, Agent::Setting.find_by(entity: ActsAsTenant.current_tenant) || Agent::Setting.new)
    return warn_about(review) if !review.clear? && (review.blocked? || params[:confirm_sensitive] != "1")

    quota = Agent::Quota.check(user: current_user, entity: ActsAsTenant.current_tenant)
    return refuse(Agent::Quota.message(quota)) if quota

    @conversation.update!(title: @question.truncate(60)) if @conversation.title.blank?
    @conversation.start_answering!
    # ponytail: a one second head start, so that the live bubble is on the page before the first piece of text is sent; a reload shows the answer if it is missed.
    Agent::AnswerJob.set(wait: 1.second).perform_later(@conversation, @question, I18n.locale.to_s)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to agent_conversation_path(@conversation), status: :see_other }
    end
  end

  # What was sent to the model for an answer, after masking: the tokens it saw, never the names.
  def sent
    @message = find_conversation.messages.assistant.find(params[:id])
    @payload = @message.sent_payload.present? ? JSON.parse(@message.sent_payload) : nil
  end

  # "Check": the tool calls of an answer replayed, to say whether the figures are still the ones the books give.
  def verify
    @message = find_conversation.messages.assistant.find(params[:id])
    @result = Agent::Verification.call(message: @message, context: agent_context)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("agent_message_#{@message.id}_verification", partial: "agent/messages/verification", locals: { message: @message, result: @result }) }
      format.html { render partial: "agent/messages/verification", locals: { message: @message, result: @result } }
    end
  end

  private

  # A message that holds what must not leave as it is: the person is told, and chooses (unless it can never go).
  def warn_about(review)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("agent_conversation_#{@conversation.id}_error", partial: "agent/messages/sensitive_warning", locals: { review: review, question: @question, conversation: @conversation }), status: :unprocessable_entity }
      format.html { redirect_to agent_conversation_path(@conversation), alert: "Your message holds data that cannot be sent as it is: remove it first.", status: :see_other }
    end
  end

  def refuse(message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("agent_conversation_#{@conversation.id}_error", message), status: :unprocessable_entity }
      format.html { redirect_to agent_conversation_path(@conversation), alert: message, status: :see_other }
    end
  end
end
