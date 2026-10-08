# What the click on a proposal does (A07), with the rights of the person who clicks: the proposal is checked again against the books as they are now (a period may have been locked, an account archived since),
# and only then the draft entry or the task is created. A proposal that no longer holds stays as it was, with the reasons. The agent never calls this; a controller does, on a request of the author.
# => Result(record:, errors:)
class Agent::Proposals::Accept
  Result = Struct.new(:record, :errors) do
    def created? = errors.empty?
  end

  def self.call(proposal:, user:) = new(proposal, user).call

  # The entry of a proposal, not saved, to fill the standard entry screen with ("Modify").
  def self.prefilled_entry(proposal)
    data = proposal.data
    entry = Accounting::JournalEntry.new(journal: Accounting::Journal.find_by(code: data["journal"]), fiscal_year_id: data["fiscal_year_id"], entry_date: data["entry_date"],
                                         description: [ data["description"], data["reference"] ].compact_blank.join(" - ").first(200))
    data["lines"].each do |line|
      entry.lines.build(account: Accounting::Account.find_by(code: line["account"]), partner_id: line["partner_id"], debit: line["debit"], credit: line["credit"], label: line["label"])
    end
    entry
  end

  # The person changed the proposal in the standard screen: the entry they saved is theirs; what differs from the proposal is kept (the outcome is data for the evaluation, never a setting).
  def self.modified!(proposal, entry)
    data = proposal.data
    now = ->(line) { [ line.account.code, line.debit.to_d.to_s("F"), line.credit.to_d.to_s("F"), line.partner_id ] }
    proposed = data["lines"].map { |line| [ line["account"], BigDecimal(line["debit"]).to_s("F"), BigDecimal(line["credit"]).to_s("F"), line["partner_id"] ] }
    changed = []
    changed << "journal" unless entry.journal.code == data["journal"]
    changed << "entry_date" unless entry.entry_date.iso8601 == data["entry_date"]
    changed << "description" unless entry.description == [ data["description"], data["reference"] ].compact_blank.join(" - ").first(200)
    changed << "lines" unless entry.lines.map(&now).sort_by(&:to_s) == proposed.sort_by(&:to_s)
    proposal.created!(entry, outcome: changed.empty? ? "accepted_as_is" : "modified", changed: changed)
    Accounting::AuditLog.record!(auditable: entry, action: "entry_via_agent_proposal", user: entry.created_by, payload: { proposal_id: proposal.id, via: "agent", changed_fields: changed })
  end

  def initialize(proposal, user)
    @proposal = proposal
    @user = user
  end

  def call
    return Result.new(nil, [ "Only the author of the conversation can decide this proposal." ]) unless @proposal.decidable_by?(@user)

    context = Agent::Context.build(user: @user, entity: ActsAsTenant.current_tenant, locale: I18n.locale)
    case @proposal.kind
    when "task" then task(context)
    when "note" then note(context)
    else entry(context)
    end
  end

  private

  def entry(context)
    checked = Agent::Proposals::Entry.call(Agent::Proposals::Entry.input_from(@proposal.data), context: context)
    return Result.new(nil, checked.errors) unless checked.valid?

    draft = Accounting::CreateDraftEntry.call(attributes: attributes_of(checked.normalized), user: @user, source: [ "Agent::Proposal", @proposal.id ])
    return Result.new(nil, draft.entry.errors.full_messages) unless draft.saved?

    record(draft.entry, "accepted_as_is", "entry_draft_via_agent", entry_id: draft.entry.id)
  end

  def task(context)
    checked = Agent::Proposals::Task.call(@proposal.data.slice("title", "priority", "due_on", "rationale", "certainty").merge("kind" => @proposal.data["task_kind"], "target" => @proposal.data["target_ref"]), context: context)
    return Result.new(nil, checked.errors) unless checked.valid?

    data = checked.normalized
    task = Accounting::Task.new(title: data["title"], kind: data["task_kind"], priority: data["priority"], due_on: data["due_on"], author: @user, description: data["rationale"], status: :open,
                                target_type: data["target_type"], target_id: data["target_id"])
    return Result.new(nil, [ "The person may not create tasks about this." ]) unless Accounting::TaskPolicy.new(@user, task).create?
    return Result.new(nil, task.errors.full_messages) unless task.save

    record(task, "accepted_as_is", "task_via_agent", task_id: task.id)
  end

  # A note is kept only by a person who may manage the memory of the file; the text can be corrected first (see Modify), this is the click as it stands.
  def note(context)
    return Result.new(nil, [ "Only a person who manages the memory of the file can keep a note." ]) unless context.allows?("agent.memory.manage")

    checked = Agent::Proposals::Note.call(@proposal.data.slice("scope_kind", "text", "category", "valid_until", "rationale").merge("object_id" => @proposal.data["object_id"]), context: context)
    return Result.new(nil, checked.errors) unless checked.valid?

    data = checked.normalized
    note = Agent::MemoryNote.create(scope_kind: data["scope_kind"], scope_id: data["object_id"], text: data["text"], category: data["category"], valid_until: data["valid_until"], author: @user, source: "proposal",
                                    proposal_id: @proposal.id, confirmed_at: Time.current)
    return Result.new(nil, note.errors.full_messages) unless note.persisted?

    record(note, "accepted_as_is", "memory_note_via_agent", note_id: note.id)
  end

  def record(created, outcome, action, **details)
    @proposal.created!(created, outcome: outcome)
    Accounting::AuditLog.record!(auditable: created, action: action, user: @user, payload: { proposal_id: @proposal.id, via: "agent", **details })
    Result.new(created, [])
  end

  # The draft as the entry screen would receive it: the euros on the side of each line, the foreign amount signed like the line, the VAT grid and its amount.
  def attributes_of(data)
    description = [ data["description"], data["reference"] ].compact_blank.join(" - ").first(200)
    { journal_id: Accounting::Journal.find_by!(code: data["journal"]).id, fiscal_year_id: data["fiscal_year_id"], entry_date: data["entry_date"], description: description,
      lines_attributes: data["lines"].each_with_index.to_h { |line, index| [ index.to_s, line_attributes(line) ] } }
  end

  def line_attributes(line)
    attributes = { account_id: Accounting::Account.find_by!(code: line["account"]).id, partner_id: line["partner_id"], debit: line["debit"], credit: line["credit"], label: line["label"],
                   vat_code: line["vat_grid"], vat_amount: line["vat_amount"], due_date: line["due_date"] }.compact
    return attributes unless line["currency"]

    amount = BigDecimal(line["amount_currency"])
    attributes.merge(currency: line["currency"], amount_currency: line["side"] == "credit" ? -amount : amount, exchange_rate: line["exchange_rate"])
  end
end
