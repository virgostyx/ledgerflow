# A question put to the agent through the API (A01): accepted (202) and answered in the background; the caller reads the conversation until it is no longer answering. The same review of what
# is typed as in the panel, the same quotas, and a repeated Idempotency-Key does not ask twice.
class Api::V1::Public::AgentMessagesController < Api::V1::Public::AgentBaseController
  self.action_scopes = { create: "agent:use" }

  def create
    conversation = conversations.find(params[:id])
    idempotently do
      question = params[:question].to_s.strip
      next unprocessable("This conversation is archived: open a new one.") if conversation.archived?
      next unprocessable("The question is empty.") if question.blank?
      next unprocessable("The question is too long: #{Agent::MessagesController::MAX_LENGTH} characters at most.") if question.length > Agent::MessagesController::MAX_LENGTH
      next unless sensitive_ok?(question)

      quota = Agent::Quota.check(user: @api_client.owner, entity: ActsAsTenant.current_tenant)
      next problem(:too_many_requests, "Quota reached", detail: Agent::Quota.message(quota), slug: "agent-quota", reason: quota) if quota

      conversation.update!(title: question.truncate(60)) if conversation.title.blank?
      conversation.start_answering!
      Agent::AnswerJob.perform_later(conversation, question, "en")
      response.set_header("Location", "/api/v1/agent/conversations/#{conversation.id}")
      render json: { data: { conversation_id: conversation.id, status: "answering" } }, status: :accepted
    end
  end

  private

  # What the question holds that must not leave as it is: refused with what was found, until the caller confirms; never, for what the entity does not let go.
  def sensitive_ok?(question)
    review = Agent::SensitiveInput.review(question, Agent::Setting.find_by(entity: ActsAsTenant.current_tenant) || Agent::Setting.new)
    return true if review.clear? || (!review.blocked? && params[:confirm_sensitive] == true)

    findings = review.findings.map { |finding| { kind: finding.kind, effect: finding.effect, count: finding.count } }
    slug = review.blocked? ? "sensitive-data-blocked" : "sensitive-data"
    detail = review.blocked? ? "The question holds data that cannot be sent: remove it." : "The question holds data that needs your confirmation: send it again with confirm_sensitive set to true."
    problem(:unprocessable_content, "Sensitive data", detail: detail, slug: slug, findings: findings)
    false
  end
end
