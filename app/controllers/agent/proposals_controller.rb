# The decision on what the agent proposed (A07). Only the author of the conversation decides; the click is checked again against the books as they are now and done with the rights of the person
# (Agent::Proposals::Accept); nothing the agent does reaches the books without it. Rejecting asks for no reason, and keeps the reason if there is one.
class Agent::ProposalsController < Agent::BaseController
  before_action :expire_due
  before_action :set_proposal, only: %i[accept reject modify]

  def accept
    return back(@proposal, alert: "Read the justification first: this amount needs a closer look.") if @proposal.review_required && params[:justification_read] != "1"

    result = Agent::Proposals::Accept.call(proposal: @proposal, user: current_user)
    if result.created?
      redirect_to destination(result.record), notice: created_notice(result.record), status: :see_other
    else
      back(@proposal, alert: "Not created: #{result.errors.to_sentence}")
    end
  end

  def reject
    return back(@proposal, alert: "This proposal can no longer be decided.") unless @proposal.decidable_by?(current_user)

    @proposal.reject!(params[:reason])
    Accounting::AuditLog.record!(auditable: @proposal, action: "agent_proposal_reject", user: current_user, payload: { kind: @proposal.kind })
    back(@proposal, notice: "Proposal rejected.")
  end

  # The standard entry screen, filled with the proposal; what the person saves there is theirs.
  def modify
    return back(@proposal, alert: "This proposal can no longer be decided.") unless @proposal.decidable_by?(current_user) && %w[entry_draft note].include?(@proposal.kind)

    redirect_to (@proposal.kind == "note" ? new_agent_memory_note_path(proposal_id: @proposal.id) : new_accounting_journal_entry_path(agent_proposal_id: @proposal.id)), status: :see_other
  end

  # "Create all drafts": the proposals of one answer that have no warning, after the person confirmed the number.
  def accept_all
    message = Agent::Message.joins(:conversation).where(agent_conversations: { user_id: current_user.id }).find(params[:message_id])
    proposals = message.proposals.live.where(kind: "entry_draft", warnings_present: false, review_required: false).order(:id).to_a
    return back(message.proposals.first, alert: "Confirm the number of drafts to create.") unless params[:confirm_count].to_i == proposals.size && proposals.any?

    results = proposals.map { |proposal| Agent::Proposals::Accept.call(proposal: proposal, user: current_user) }
    failed = results.count { |result| !result.created? }
    back(proposals.first, notice: "#{results.size - failed} draft(s) created.#{" #{failed} could not be created and are left as they are." if failed.positive?}")
  end

  private

  def expire_due = Agent::Proposal.expire_due!

  def set_proposal = @proposal = Agent::Proposal.where(user_id: current_user.id).find(params[:id])

  def back(proposal, **flash)
    redirect_to proposal&.conversation_id ? agent_conversation_path(proposal.conversation_id) : agent_conversations_path, flash: flash, status: :see_other
  end

  def created_notice(record)
    case record
    when Accounting::JournalEntry then "The draft was created. It is not validated: that stays your decision."
    when Agent::MemoryNote then "The note was kept."
    else "The task was created."
    end
  end

  def destination(record)
    case record
    when Accounting::JournalEntry then accounting_journal_entry_path(record)
    when Agent::MemoryNote then edit_agent_memory_note_path(record)
    else accounting_task_path(record)
    end
  end
end
