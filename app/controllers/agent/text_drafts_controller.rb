# The texts the assistant drafted for a person (A11): theirs alone. The person reads, changes, copies, uses it in the reminder of F09 or in a task of F08, asks for another version, or rejects it. The assistant sends nothing:
# a reminder that carries its text goes through the validation of a person like any other, and never through the automatic sending.
class Agent::TextDraftsController < Agent::BaseController
  before_action :set_draft, except: :index

  INSTRUCTIONS = { "firmer" => "make it firmer, without adding any threat, interest or deadline that was not given", "softer" => "make it softer and more courteous", "shorter" => "make it shorter",
                   "translate_nl" => "translate it into Dutch", "translate_fr" => "translate it into French", "translate_en" => "translate it into English" }.freeze

  def index
    @drafts = Agent::TextDraft.where(user_id: current_user.id).includes(:partner).recent.limit(100)
  end

  def show
    @previous = @draft.versions[-2]
    @removed, @added = diff(@previous["body"], @draft.body) if @previous
    @items = reminder_items
    @tasks = task_targets
  end

  # The person's own changes: a new version, the older ones kept.
  def update
    return back("This draft is closed.") unless @draft.draft?

    @draft.add_version!(subject: params[:subject].to_s.squish.first(200).presence, body: params[:body].to_s.strip.first(Agent::Proposals::Text::MAX_BODY), by: "person")
    redirect_to agent_text_draft_path(@draft), notice: "Saved as a new version.", status: :see_other
  end

  def use_in_reminder
    item = reminder_items.find { |row| row.id == params[:item_id].to_i } or return back("Choose a reminder that is still waiting for validation.")
    return back("Fill the placeholders [To complete: …] first.") if @draft.body.match?(Agent::Proposals::Text::PLACEHOLDER)

    authorize item, :update?, policy_class: Accounting::DunningRunPolicy
    result = Accounting::UpdateDunningItem.call(item: item, subject: @draft.subject_line.presence || item.subject, body: @draft.body)
    return back(result.message) if result.failure?

    item.update_columns(agent_draft_id: @draft.id)
    @draft.use!("reminder", @draft.body)
    Accounting::AuditLog.record!(auditable: item, action: "dunning_text_from_agent", user: current_user, payload: { draft_id: @draft.id })
    redirect_to accounting_dunning_item_path(item), notice: "The text is in the reminder. It still has to be validated by a person, like any reminder; the automatic sending never takes it.", status: :see_other
  end

  def save_in_task
    task = task_targets.find { |row| row.id == params[:task_id].to_i } or return back("Choose a task.")
    authorize task, :comment?, policy_class: Accounting::TaskPolicy
    return back("Fill the placeholders [To complete: …] first.") if @draft.body.match?(Agent::Proposals::Text::PLACEHOLDER)

    Accounting::Comment.create!(commentable: task, body: @draft.body, author: current_user)
    @draft.use!("comment", @draft.body)
    redirect_to accounting_task_path(task), notice: "Saved in the task.", status: :see_other
  end

  def copied
    @draft.use!("copied", params[:text].presence || @draft.body) if @draft.draft?
    head :no_content
  end

  def reject
    @draft.reject! if @draft.draft?
    redirect_to agent_text_drafts_path, notice: "Draft rejected.", status: :see_other
  end

  # Another version, on an instruction: the assistant is asked in a conversation of its own, with a question the server writes.
  def regenerate
    instruction = INSTRUCTIONS[params[:instruction].to_s] || params[:custom].to_s.squish.first(200).presence
    return back("Choose how to change the text.") unless instruction && @draft.draft?
    return back(Agent::Quota.message(Agent::Quota.check(user: current_user, entity: ActsAsTenant.current_tenant))) if Agent::Quota.check(user: current_user, entity: ActsAsTenant.current_tenant)

    question = "Revise my draft ##{@draft.id} (use get_text_draft, then propose_text with revises #{@draft.id}): #{instruction}."
    conversation = Agent::Conversation.create!(user: current_user, origin_screen: "agent/text_drafts#show", context_ref: { "type" => "draft", "id" => @draft.id.to_s }, title: question.truncate(60))
    conversation.start_answering!
    Agent::AnswerJob.set(wait: 1.second).perform_later(conversation, question, I18n.locale.to_s)
    flash[:pending_question] = question
    redirect_to agent_conversation_path(conversation), status: :see_other
  end

  private

  def set_draft = @draft = Agent::TextDraft.where(user_id: current_user.id).find(params[:id])

  def back(message) = redirect_to(agent_text_draft_path(@draft), alert: message, status: :see_other)

  # The reminders of this customer that wait for a person to validate them (F09), if the person may prepare them.
  def reminder_items
    return [] unless @draft.kind == "dunning_letter" && @draft.partner_id && current_user && Accounting::DunningRunPolicy.new(current_user, nil).update?

    Accounting::DunningItem.pending.where(partner_id: @draft.partner_id, excluded: false).includes(:run).order(:id).to_a
  end

  def task_targets
    return [] unless @draft.partner_id

    Accounting::Task.visible_to(current_user).open_ones.where(target_type: "Accounting::Partner", target_id: @draft.partner_id).order(:id).to_a
  end

  # Lines in one version and not in the other (not an aligned diff: the same choice as the versions of the knowledge base).
  def diff(old, new)
    a, b = [ old, new ].map { |text| text.to_s.lines.map(&:strip).reject(&:empty?) }
    [ a - b, b - a ]
  end
end
