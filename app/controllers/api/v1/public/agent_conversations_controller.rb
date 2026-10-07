# The conversations of the owner of the token with the agent (A01): open, list, read, rename or archive, delete, stop. What is said in a conversation goes through AgentMessagesController.
class Api::V1::Public::AgentConversationsController < Api::V1::Public::AgentBaseController
  self.action_scopes = { index: "agent:use", show: "agent:use", create: "agent:use", update: "agent:use", destroy: "agent:use", stop: "agent:use" }

  SORTS = { "id" => "agent_conversations.id", "updated_at" => "agent_conversations.updated_at" }.freeze
  FILTERS = { "status" => ->(scope, value) { scope.where(status: value) } }.freeze

  def index
    page = paginate(conversations, sorts: SORTS, filters: FILTERS, default_sort: "-updated_at")
    return if performed?

    render json: { data: page[:rows].map { |conversation| conversation_json(conversation) }, meta: page[:meta] }
  end

  def show
    conversation = conversations.find(params[:id])
    response.set_header("ETag", etag_of(conversation))
    render json: { data: conversation_json(conversation, messages: true) }
  end

  def create
    screen, subject_type, subject_id = params.dig(:conversation, :screen), params.dig(:conversation, :subject_type), params.dig(:conversation, :subject_id)
    malformed = (screen.present? && !screen.to_s.match?(SCREEN)) || ((subject_type.present? || subject_id.present?) && !(subject_type.to_s.match?(REFERENCE) && subject_id.to_s.match?(REFERENCE)))
    return unprocessable("screen or subject is not shaped like one") if malformed

    conversation = conversations.create!(user: @api_client.owner, origin_screen: screen.presence, context_ref: subject_type.present? ? { "type" => subject_type.to_s, "id" => subject_id.to_s } : {})
    response.set_header("Location", "/api/v1/agent/conversations/#{conversation.id}")
    render json: { data: conversation_json(conversation) }, status: :created
  end

  def update
    conversation = conversations.find(params[:id])
    return unless require_current!(etag_of(conversation))

    conversation.update!(title: params[:title].to_s.strip.first(120)) if params[:title].present?
    conversation.archive! if params[:archived] == true
    response.set_header("ETag", etag_of(conversation))
    render json: { data: conversation_json(conversation) }
  end

  def destroy
    conversations.find(params[:id]).destroy!
    head :no_content
  end

  def stop
    conversations.find(params[:id]).request_stop!
    head :no_content
  end
end
