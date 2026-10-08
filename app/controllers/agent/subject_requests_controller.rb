# An owner's search for a natural person in the conversations of the entity, to export what concerns them or to erase it (A04, the right of access and of erasure). Each export or erasure
# needs a reason and leaves a line in the audit trail that holds a fingerprint of the name, not the name.
class Agent::SubjectRequestsController < ApplicationController
  before_action { require_feature!(:agent) }
  before_action { authorize :agent, :configure? }

  def new; end

  def create
    @name = params[:name].to_s.squish
    @conversations = Agent::SubjectSearch.conversations(@name).includes(:user)
    @related = Agent::SubjectSearch.related(@name)
    operation = params[:operation].to_s
    return render :new, status: :ok if operation == "search" || @name.blank?
    return reject("Give the reason of the request: it is written in the audit trail.") if params[:reason].to_s.squish.blank?

    trace(operation)
    operation == "erase" ? erase : export
  end

  private

  def export
    data = Agent::Export.conversations(@conversations, with_author: true).merge(Agent::Export.related(@related))
    send_data JSON.pretty_generate(data), type: "application/json", disposition: "attachment", filename: "agent-subject-request-#{Date.current.iso8601}.json"
  end

  def erase
    count = @conversations.count
    other = @related.count
    @conversations.find_each(&:destroy!)
    @related.to_a.each { |records| records.each(&:destroy!) }
    redirect_to new_agent_subject_request_path, notice: "#{count} conversation(s) and #{other} other record(s) (notes, summaries, proposals, readings) erased.", status: :see_other
  end

  def trace(operation)
    Accounting::AuditLog.record!(auditable: ActsAsTenant.current_tenant, action: "agent_subject_request", user: current_user, reason: params[:reason].to_s.squish.first(500),
                                 payload: { operation: operation, subject_fingerprint: Digest::SHA256.hexdigest(@name.downcase)[0, 16], conversations: @conversations.count, other_records: @related.count })
  end

  def reject(message)
    @error = message
    render :new, status: :unprocessable_entity
  end
end
