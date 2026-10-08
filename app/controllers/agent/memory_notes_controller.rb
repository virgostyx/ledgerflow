# The memory of the file (A10b): everything the assistant may know of this entity beyond the books, written or confirmed by a person, all of it here. Seen by whoever may use the assistant, changed by those who
# manage the memory (`agent.memory.manage`). A note is never created by the assistant: it proposes, and a person reads, corrects and confirms. Deleting a note deletes it.
class Agent::MemoryNotesController < Agent::BaseController
  before_action(except: %i[index export]) { authorize :agent, :manage_memory? }
  before_action :set_note, only: %i[edit update archive destroy]

  def index
    notes = Agent::MemoryNote.includes(:author).ordered
    notes = notes.where(scope_kind: params[:scope_kind]) if Agent::MemoryNote::SCOPES.include?(params[:scope_kind])
    notes = notes.where(category: params[:category]) if Agent::MemoryNote::CATEGORIES.include?(params[:category])
    notes = notes.where(status: params[:status]) if Agent::MemoryNote::STATUSES.include?(params[:status])
    @notes = params[:q].present? ? notes.select { |note| note.text.downcase.include?(params[:q].to_s.downcase) } : notes.to_a # the text is encrypted: searched here
    @suggested = Agent::MemoryNote.unused.includes(:author).ordered.to_a
    @manage = policy(:agent).manage_memory?
  end

  def new
    @note = Agent::MemoryNote.new(scope_kind: params[:scope_kind].presence_in(Agent::MemoryNote::SCOPES) || "entity", scope_id: params[:scope_id], category: "other", text: prefilled_text)
    @proposal = live_proposal(params[:proposal_id])
    prefill_from(@proposal) if @proposal
  end

  def create
    @proposal = live_proposal(params[:proposal_id])
    @note = Agent::MemoryNote.new(note_params.merge(author: current_user, source: @proposal ? "proposal" : "manual", proposal_id: @proposal&.id, confirmed_at: Time.current))
    if @note.save
      @proposal&.created!(@note, outcome: changed_from(@proposal, @note).empty? ? "accepted_as_is" : "modified", changed: changed_from(@proposal, @note))
      Accounting::AuditLog.record!(auditable: @note, action: "memory_note_add", user: current_user, payload: { scope: @note.scope_kind, source: @note.source })
      redirect_to agent_memory_notes_path, notice: "Note kept.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @note.update(note_params)
      Accounting::AuditLog.record!(auditable: @note, action: "memory_note_update", user: current_user, payload: { scope: @note.scope_kind })
      redirect_to agent_memory_notes_path, notice: "Note updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def archive
    @note.update!(status: "archived")
    redirect_to agent_memory_notes_path, notice: "Note archived: the assistant no longer reads it.", status: :see_other
  end

  # Gone for good: nothing of it is kept, except the line of the audit trail that says a note was deleted.
  def destroy
    Accounting::AuditLog.record!(auditable: @note, action: "memory_note_delete", user: current_user, payload: { scope: @note.scope_kind })
    @note.destroy!
    redirect_to agent_memory_notes_path, notice: "Note deleted.", status: :see_other
  end

  def export
    send_data JSON.pretty_generate(Agent::Export.memory(Agent::MemoryNote.includes(:author).ordered)), type: "application/json", disposition: "attachment", filename: "agent-memory-#{Date.current.iso8601}.json"
  end

  private

  def set_note = @note = Agent::MemoryNote.find(params[:id])

  def note_params
    permitted = params.require(:agent_memory_note).permit(:scope_kind, :text, :category, :valid_until, :partner_id, :account_id)
    scope_id = { "partner" => permitted[:partner_id], "account" => permitted[:account_id] }[permitted[:scope_kind]].presence
    permitted.slice(:scope_kind, :text, :category, :valid_until).merge(scope_id: scope_id)
  end

  def live_proposal(id) = (Agent::Proposal.live.where(user_id: current_user.id, kind: "note").find_by(id: id) if id.present?)

  def prefill_from(proposal)
    data = proposal.data
    @note.assign_attributes(scope_kind: data["scope_kind"], scope_id: data["object_id"], text: data["text"], category: data["category"], valid_until: data["valid_until"])
  end

  # "Remember this", under an answer of the person's own: the words of the answer as a start, to be cut and corrected.
  def prefilled_text
    return unless params[:message_id].present?

    message = Agent::Message.joins(:conversation).where(agent_conversations: { user_id: current_user.id }).assistant.find_by(id: params[:message_id])
    message && message.conversation.reveal(message.content).gsub(Agent::Citations::MARKER, "").squish.first(Agent::MemoryNote::MAX_LENGTH)
  end

  def changed_from(proposal, note)
    data = proposal.data
    { "scope_kind" => note.scope_kind, "text" => note.text, "category" => note.category, "valid_until" => note.valid_until&.iso8601 }.reject { |key, value| data[key] == value }.keys
  end
end
