# Opening, resuming, renaming, archiving and deleting one's conversations with the agent (A01).
class Agent::ConversationsController < Agent::BaseController
  EXPLAIN_QUESTION = "Explain this figure.".freeze
  # The question is the same every time for a kind of object, whatever the button sent.
  # The texts the assistant may be asked to draft from a button (A11): the question is fixed on the server.
  WRITE_QUESTIONS = { "dunning_letter" => "Write the reminder for this customer.", "client_request" => "Write a request for the missing documents to this partner." }.freeze
  EXPLAIN_QUESTIONS = { "R19" => "Explain this anomaly.", "R19top" => "Explain the five first open anomalies, in the order to fix them.", "I7" => "Explain this difference.", "doc" => "Prepare the entry for this document.", "entry" => "Explain this entry: who made it, when it was validated and what it changed." }.freeze
  # What changed between two moments (B03b): the question names the two instants, read from the reference by its shape only, never as free text.
  CHANGES_REFERENCE = /\A\d+:(?<from>\d{8}T\d{6}Z):(?<to>\d{8}T\d{6}Z|now)\z/

  def index
    @screen = params[:screen].to_s[SCREEN]
    @conversations = conversations.active.order(updated_at: :desc).limit(50)
  end

  def show
    @conversation = find_conversation
    @messages = @conversation.messages.where(role: %w[user assistant]).includes(:tool_calls, :proposals, :text_drafts).order(:id)
    @context = agent_context(screen: @conversation.origin_screen, subject_ref: @conversation.context_ref)
    @reviews = @conversation.reviews.includes(:reviewer).order(:reviewed_at)
  end

  # A reference to the object the panel is opened on is kept only if it is shaped like one (a type and an identifier), never as text copied from the screen.
  def create
    reference = { "type" => params[:subject_type].to_s[REFERENCE], "id" => params[:subject_id].to_s[REFERENCE] }
    conversation = conversations.create!(user: current_user, origin_screen: params[:screen].to_s[SCREEN], context_ref: reference.values.all? ? reference : {})
    asked = Agent::Digest::Sources::ASK[params[:ask].to_s] || WRITE_QUESTIONS[params[:write].to_s] # a question of the summary or of a button to write: fixed on the server, the page only names it
    if asked
      ask_to_explain(conversation, asked)
    elsif params[:explain] == "1"
      ask_to_explain(conversation, explain_question(reference))
    end
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

  def explain_question(reference)
    return EXPLAIN_QUESTIONS.fetch(reference["type"], EXPLAIN_QUESTION) unless reference["type"] == "R21" && (moments = CHANGES_REFERENCE.match(reference["id"].to_s))

    stamp = ->(text) { Time.utc(text[0, 4], text[4, 2], text[6, 2], text[9, 2], text[11, 2], text[13, 2]).iso8601 } # the Z is UTC: no local zone in it
    to = moments[:to] == "now" ? "now" : stamp.(moments[:to])
    "Explain what changed in the books between #{stamp.(moments[:from])} and #{to}."
  rescue ArgumentError # a date that does not exist
    EXPLAIN_QUESTION
  end

  # The "Explain" button of a figure: the question is the same every time, whatever the button sent, and the answer is started at once. The panel shows the question and the live bubble.
  def ask_to_explain(conversation, question)
    return if Agent::Quota.check(user: current_user, entity: ActsAsTenant.current_tenant)

    conversation.update!(title: question.truncate(60))
    conversation.start_answering!
    Agent::AnswerJob.set(wait: 1.second).perform_later(conversation, question, I18n.locale.to_s)
    flash[:pending_question] = question
  end
end
