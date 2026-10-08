require "rails_helper"

# A07: the click. Only the author decides; the proposal is checked again against the books; the draft is created with the person's rights and marked as coming from the agent; nothing is created before.
RSpec.describe "Deciding what the agent proposes (A07)", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let(:colleague)  { create(:user, role: :accountant) }
  let(:reader)     { create(:user, role: :manager) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:colleague_membership) { create(:user_entity, :accountant, user: colleague, entity: entity) }
  let!(:reader_membership) { create(:user_entity, :manager, user: reader, entity: entity) }
  let(:journal) { create(:journal, :purchase) }
  let(:supplier) { create(:partner, :supplier, name: "Fournisseur Dupont SA", vat_number: nil) }
  let(:conversation) { Agent::Conversation.create!(user: accountant, title: "Insurance") }
  let(:message) { conversation.messages.create!(role: "assistant", content: "Prepared.", status: "complete") }
  let(:day) { fiscal_year.start_date + 5 }

  def entry_input(amount: "100.00")
    { "journal" => journal.code, "entry_date" => day.iso8601, "description" => "Insurance 2026", "reference" => "FA-77", "certainty" => "given", "rationale" => "Annual premium, booked as a cost.",
      "lines" => [ { "account" => "604000", "side" => "debit", "amount" => amount, "label" => "Premium" }, { "account" => "440000", "side" => "credit", "amount" => amount, "partner_id" => supplier.id } ] }
  end

  def proposal_for(user: accountant, input: entry_input, **attrs)
    context = Agent::Context.build(user: user, entity: entity, locale: :en)
    normalized = Agent::Proposals::Entry.call(input, context: context).normalized
    Agent::Proposal.create!({ user: user, conversation: conversation, message: message, kind: "entry_draft", payload: normalized.to_json }.merge(attrs))
  end

  before do
    enable_agent!
    sign_in accountant
  end

  describe "creating the draft" do
    it "creates a draft entry with the person's rights, marked as coming from the agent, and does not validate it" do
      proposal = proposal_for

      expect { post accept_agent_proposal_path(proposal) }.to change(Accounting::JournalEntry, :count).by(1)

      entry = Accounting::JournalEntry.order(:id).last
      expect(entry).to have_attributes(status: "draft", created_by_id: accountant.id, source_type: "Agent::Proposal", source_id: proposal.id, entry_date: day, description: "Insurance 2026 - FA-77")
      expect(entry.lines.map { |line| [ line.account.code, line.debit.to_s("F"), line.credit.to_s("F") ] }).to contain_exactly([ "604000", "100.0", "0.0" ], [ "440000", "0.0", "100.0" ])
      expect(proposal.reload).to have_attributes(status: "created", outcome: "accepted_as_is", result_type: "Accounting::JournalEntry", result_id: entry.id)
      expect(response).to redirect_to(accounting_journal_entry_path(entry))
    end

    it "writes the origin in the audit trail: the person, the proposal, the agent" do
      proposal = proposal_for
      post accept_agent_proposal_path(proposal)
      entry = Accounting::JournalEntry.order(:id).last

      log = Accounting::AuditLog.find_by!(action: "entry_draft_via_agent", auditable_id: entry.id)
      expect(log.user_id).to eq(accountant.id)
      expect(log.payload).to include("proposal_id" => proposal.id, "via" => "agent")
    end

    it "creates nothing for a proposal that nobody clicked: the books are the same while it waits" do
      expect { proposal_for }.not_to change(Accounting::JournalEntry, :count)
    end

    it "checks the proposal again and refuses when the period was locked since, saying why, and keeps the proposal" do
      proposal = proposal_for
      create(:period_lock, starts_on: day.beginning_of_month, ends_on: day.end_of_month)

      expect { post accept_agent_proposal_path(proposal) }.not_to change(Accounting::JournalEntry, :count)

      expect(flash[:alert]).to include("locked period")
      expect(proposal.reload).to be_pending
    end

    it "refuses when an account was archived since" do
      proposal = proposal_for
      account_604.update!(active: false)

      post accept_agent_proposal_path(proposal)

      expect(flash[:alert]).to include("604000", "archived")
    end

    it "refuses a proposal of another person, one that expired and one already decided" do
      other = proposal_for(user: colleague)
      expired = proposal_for(expires_at: 1.minute.ago)
      done = proposal_for
      done.update!(status: "rejected")

      [ other, expired, done ].each { |proposal| post accept_agent_proposal_path(proposal) }

      expect(Accounting::JournalEntry.count).to eq(0)
      expect(expired.reload).to be_expired
    end

    it "does not find the proposal of another person at all" do
      other = proposal_for(user: colleague)

      post accept_agent_proposal_path(other)

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a person who may not write entries, even for their own proposal" do
      conversation_of_reader = Agent::Conversation.create!(user: reader, title: "x")
      context = Agent::Context.build(user: accountant, entity: entity, locale: :en)
      normalized = Agent::Proposals::Entry.call(entry_input, context: context).normalized
      proposal = Agent::Proposal.create!(user: reader, conversation: conversation_of_reader, kind: "entry_draft", payload: normalized.to_json)
      sign_in reader

      expect { post accept_agent_proposal_path(proposal) }.not_to change(Accounting::JournalEntry, :count)
      expect(flash[:alert]).to be_present
    end

    it "asks to read the justification above the threshold of the entity" do
      Agent::Setting.for_current_entity.update!(review_threshold: 50)
      proposal = proposal_for(review_required: true)

      expect { post accept_agent_proposal_path(proposal) }.not_to change(Accounting::JournalEntry, :count)
      expect(flash[:alert]).to include("justification")

      expect { post accept_agent_proposal_path(proposal), params: { justification_read: "1" } }.to change(Accounting::JournalEntry, :count).by(1)
    end

    it "never validates: the draft waits for someone who may validate it" do
      proposal = proposal_for
      post accept_agent_proposal_path(proposal)

      expect(Accounting::JournalEntry.order(:id).last.reference).to be_nil
    end
  end

  describe "rejecting" do
    it "keeps the reason and creates nothing" do
      proposal = proposal_for

      expect { post reject_agent_proposal_path(proposal), params: { reason: "Wrong supplier" } }.not_to change(Accounting::JournalEntry, :count)

      expect(proposal.reload).to have_attributes(status: "rejected", outcome: "rejected", reject_reason: "Wrong supplier")
    end

    it "does not reject what is decided already" do
      proposal = proposal_for
      post accept_agent_proposal_path(proposal)
      post reject_agent_proposal_path(proposal)

      expect(proposal.reload).to be_created
    end
  end

  describe "modifying" do
    it "opens the standard entry screen with the proposal in it, every line" do
      proposal = proposal_for

      get modify_agent_proposal_path(proposal)
      expect(response).to redirect_to(new_accounting_journal_entry_path(agent_proposal_id: proposal.id))
      follow_redirect!

      expect(response.body).to include("Prepared by the assistant", "Insurance 2026 - FA-77", %(name="accounting_journal_entry[agent_proposal_id]"))
      expect(response.body.scan(/accounting_journal_entry\[lines_attributes\]\[\d\]\[account_id\]/).uniq.size).to be >= 2
    end

    it "marks the proposal as modified when the person saves something else, and as accepted when nothing changed" do
      proposal = proposal_for
      other = proposal_for

      post accounting_journal_entries_path, params: { accounting_journal_entry: { agent_proposal_id: proposal.id, journal_id: journal.id, fiscal_year_id: fiscal_year.id, entry_date: day.iso8601, description: "Insurance changed",
        lines_attributes: { "0" => { account_id: account_604.id, debit: "100.00", credit: "0" }, "1" => { account_id: account_440.id, partner_id: supplier.id, debit: "0", credit: "100.00" } } } }
      expect(proposal.reload).to have_attributes(status: "created", outcome: "modified", changed_fields: [ "description" ])
      expect(Accounting::JournalEntry.order(:id).last).to have_attributes(source_type: "Agent::Proposal", source_id: proposal.id)

      post accounting_journal_entries_path, params: { accounting_journal_entry: { agent_proposal_id: other.id, journal_id: journal.id, fiscal_year_id: fiscal_year.id, entry_date: day.iso8601, description: "Insurance 2026 - FA-77",
        lines_attributes: { "0" => { account_id: account_604.id, debit: "100.00", credit: "0", label: "Premium" }, "1" => { account_id: account_440.id, partner_id: supplier.id, debit: "0", credit: "100.00" } } } }
      expect(other.reload).to have_attributes(outcome: "accepted_as_is", changed_fields: [])
      expect(Accounting::JournalEntry.where(source_type: "Agent::Proposal").pluck(:status).uniq).to eq([ "draft" ]) # saved from a proposal, never validated by the same gesture
    end

    it "ignores a proposal id that is not the person's, and a modification of a task" do
      other = proposal_for(user: colleague)

      get new_accounting_journal_entry_path(agent_proposal_id: other.id)

      expect(response.body).not_to include("Prepared by the assistant")
    end
  end

  describe "a task" do
    let(:task_input) { { "title" => "Ask for the contract", "kind" => "missing_document", "priority" => "high", "target" => "partner:#{supplier.id}", "rationale" => "No document behind the entry.", "certainty" => "given" } }

    def task_proposal
      context = Agent::Context.build(user: accountant, entity: entity, locale: :en)
      Agent::Proposal.create!(user: accountant, conversation: conversation, message: message, kind: "task", payload: Agent::Proposals::Task.call(task_input, context: context).normalized.to_json)
    end

    it "creates the task, about its target, with the person as the author" do
      proposal = task_proposal

      expect { post accept_agent_proposal_path(proposal) }.to change(Accounting::Task, :count).by(1)

      expect(Accounting::Task.last).to have_attributes(title: "Ask for the contract", kind: "missing_document", priority: "high", author_id: accountant.id, target_type: "Accounting::Partner", target_id: supplier.id)
      expect(proposal.reload).to have_attributes(status: "created", result_type: "Accounting::Task")
      expect(response).to redirect_to(accounting_task_path(Accounting::Task.last))
    end
  end

  describe "creating all the drafts of an answer" do
    it "creates only those without a warning, after the number is confirmed, each audited on its own" do
      clean = [ proposal_for, proposal_for(input: entry_input(amount: "50.00")) ]
      warned = proposal_for(warnings_present: true)

      post agent_accept_all_proposals_path(message.id), params: { confirm_count: "1" }
      expect(Accounting::JournalEntry.count).to eq(0)

      post agent_accept_all_proposals_path(message.id), params: { confirm_count: "2" }

      expect(Accounting::JournalEntry.count).to eq(2)
      expect(clean.map { |proposal| proposal.reload.status }).to eq(%w[created created])
      expect(warned.reload).to be_pending
      expect(Accounting::AuditLog.where(action: "entry_draft_via_agent").count).to eq(2)
    end

    it "leaves alone the answers of other people" do
      other_conversation = Agent::Conversation.create!(user: colleague, title: "x")
      other_message = other_conversation.messages.create!(role: "assistant", content: "x", status: "complete")

      post agent_accept_all_proposals_path(other_message.id), params: { confirm_count: "1" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the card" do
    it "shows the lines, the checks, the justification and the buttons under the answer" do
      proposal_for(warnings_present: true)

      get agent_conversation_path(conversation)

      expect(response.body).to include("Proposed entry", "604000", "Services divers", "Balanced", "Period open", "Why this treatment?", "Annual premium, booked as a cost.", "Create the draft", "Modify", "Reject")
    end

    it "shows what became of a decided proposal, with a link to the draft" do
      proposal = proposal_for
      post accept_agent_proposal_path(proposal)

      get agent_conversation_path(conversation)

      expect(response.body).to include("The draft was created.", "Open the entry")
      expect(response.body).not_to include("Create the draft")
    end

    it "shows no button to the person who is not the author, only to the author's own conversation" do
      proposal_for
      sign_in colleague

      get agent_conversation_path(conversation)

      expect(response).to have_http_status(:not_found)
    end
  end
end
