# The exceptional reading of someone else's conversation by an owner (A01). The list shows who talked, when and how much, never what was said. Reading needs a reason and a code of the
# second factor given now; it leaves a record, a line in the audit trail and a notice to the author, and stays open for half an hour for the one who asked.
class Agent::ReviewsController < ApplicationController
  before_action { require_feature!(:agent) }
  before_action { authorize :agent, :review_conversations? }

  def index
    @conversations = Agent::Conversation.where.not(user_id: current_user.id).includes(:user).left_joins(:messages).group("agent_conversations.id").select("agent_conversations.*, COUNT(agent_messages.id) AS messages_count")
                                        .order(updated_at: :desc).limit(100)
    @reviews_by_conversation = Agent::ConversationReview.where(conversation_id: @conversations.map(&:id)).group(:conversation_id).count
  end

  def create
    conversation = Agent::Conversation.find(params[:conversation_id])
    return refuse("Your own conversations are yours to read: use the assistant.", conversation) if conversation.user_id == current_user.id

    reason = params[:reason].to_s.squish
    return refuse("Say why you need to read it (at least #{Agent::ConversationReview::MIN_REASON} characters): the author is told.", conversation) if reason.length < Agent::ConversationReview::MIN_REASON
    return refuse("Enrol an authenticator app in your account first: reading someone else's conversation needs the second factor.", conversation) unless current_user.totp_enabled?
    return refuse("That code is not right, or was used already. Wait for the next one.", conversation) unless current_user.verify_totp!(params[:code])

    review = record(conversation, reason)
    redirect_to agent_review_path(review), status: :see_other
  end

  def show
    @review = Agent::ConversationReview.find(params[:id])
    return redirect_to(agent_reviews_path, alert: "This reading is not yours, or has ended. Start again.") unless @review.reviewer_id == current_user.id && @review.open?

    @conversation = @review.conversation
    @messages = @conversation.messages.where(role: %w[user assistant]).order(:id)
  end

  private

  def record(conversation, reason)
    Agent::ConversationReview.transaction do
      Agent::ConversationReview.create!(conversation: conversation, author: conversation.user, reviewer: current_user, reason: reason, message_count: conversation.messages.count, reviewed_at: Time.current).tap do |review|
        Accounting::AuditLog.record!(auditable: review, action: "agent_conversation_review", user: current_user, reason: reason, payload: { conversation_id: conversation.id, author_id: conversation.user_id, messages: review.message_count })
        Accounting::Notify.call(user: conversation.user, event: "agent_conversation_read", subject: review, data: { by: current_user.email, reason: reason })
        Agent::ReviewMailer.conversation_read(review).deliver_later
      end
    end
  end

  def refuse(message, conversation)
    @alert = message
    @conversations = Agent::Conversation.where(id: conversation.id).includes(:user)
    @reviews_by_conversation = {}
    render :index, status: :unprocessable_entity
  end
end
