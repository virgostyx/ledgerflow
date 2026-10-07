# Opening, resuming, renaming, archiving and deleting one's conversations with the agent (A01).
class Agent::ConversationsController < Agent::BaseController
  EXPLAIN_QUESTION = "Explain this figure.".freeze

  def index
    @screen = params[:screen].to_s[SCREEN]
    @conversations = conversations.active.order(updated_at: :desc).limit(50)
  end

  def show
    @conversation = find_conversation
    @messages = @conversation.messages.where(role: %w[user assistant]).includes(:tool_calls).order(:id)
    @context = agent_context(screen: @conversation.origin_screen, subject_ref: @conversation.context_ref)
    @reviews = @conversation.reviews.includes(:reviewer).order(:reviewed_at)
  end

  # A reference to the object the panel is opened on is kept only if it is shaped like one (a type and an identifier), never as text copied from the screen.
  def create
    reference = { "type" => params[:subject_type].to_s[REFERENCE], "id" => params[:subject_id].to_s[REFERENCE] }
    conversation = conversations.create!(user: current_user, origin_screen: params[:screen].to_s[SCREEN], context_ref: reference.values.all? ? reference : {})
    ask_to_explain(conversation) if params[:explain] == "1"
    redirect_to agent_conversation_path(conversation), status: :see_other
  end

  # Everything the person has said to the agent in this entity, as a file.
  def export
    data = Agent::Export.conversations(conversations)
    send_data JSON.pretty_generate(data), type: "application/json", disposition: "attachment", filename: "agent-conversations-#{Date.current.iso8601}.json"
  end

  def update
    conversation = find_conversation
    conversation.update!(title: params.dig(:agent_conversation, :title).to_s.strip.first(120).presence || conversation.title) if params.dig(:agent_conversation, :title)
    conversation.archive! if params.dig(:agent_conversation, :archived) == "1"
    redirect_to agent_conversations_path, status: :see_other
  end

  def destroy
    find_conversation.destroy!
    redirect_to agent_conversations_path, status: :see_other
  end

  private

  # The "Explain" button of a figure: the question is the same every time, whatever the button sent, and the answer is started at once. The panel shows the question and the live bubble.
  def ask_to_explain(conversation)
    return if Agent::Quota.check(user: current_user, entity: ActsAsTenant.current_tenant)

    conversation.update!(title: EXPLAIN_QUESTION.truncate(60))
    conversation.start_answering!
    Agent::AnswerJob.set(wait: 1.second).perform_later(conversation, EXPLAIN_QUESTION, I18n.locale.to_s)
    flash[:pending_question] = EXPLAIN_QUESTION
  end
end
