require "rails_helper"

# A10b: the screen of the memory of the file, the proposal to remember, and the erasure of a person: everything the assistant keeps is visible, changeable and deletable.
RSpec::Matchers.define_negated_matcher :not_include, :include

RSpec.describe "The memory of the file (A10b)", type: :request do
  include_context "with_open_fiscal_year"

  let(:owner) { create(:user, full_name: "Olivia Owner") }
  let(:accountant) { create(:user, full_name: "Julie Martin") }
  let(:reader) { create(:user) }
  let!(:owner_membership) { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:reader_membership) { create(:user_entity, :manager, user: reader, entity: entity) }
  let(:partner) { create(:partner, :customer, name: "Client Martin SRL", vat_number: nil) }
  let(:params) { { agent_memory_note: { scope_kind: "partner", partner_id: partner.id, text: "Pays at 45 days.", category: "partner" } } }

  before do
    enable_agent!
    sign_in accountant
  end

  def note(**attrs) = Agent::MemoryNote.create!({ scope_kind: "entity", text: "Invoices in euros.", category: "convention", author: accountant }.merge(attrs))

  it "keeps a note written by a person, audited, and shows it in the list with who and when" do
    expect { post agent_memory_notes_path, params: params }.to change(Agent::MemoryNote, :count).by(1)

    kept = Agent::MemoryNote.last
    expect(kept).to have_attributes(scope_kind: "partner", scope_id: partner.id, author_id: accountant.id, source: "manual", status: "active")
    expect(kept.confirmed_at).to be_present
    expect(Accounting::AuditLog.where(action: "memory_note_add", auditable_id: kept.id)).to exist
    get agent_memory_notes_path
    expect(response.body).to include("Pays at 45 days.", "Julie Martin", "Partner ##{partner.id}")
  end

  it "searches the text, and filters by about, category and status" do
    note(text: "Invoices in euros.")
    note(scope_kind: "partner", scope_id: partner.id, text: "Pays at 45 days.", category: "partner")
    note(text: "Old convention", status: "archived")

    get agent_memory_notes_path, params: { q: "45" }
    expect(response.body).to include("Pays at 45 days.").and not_include("Invoices in euros.")
    get agent_memory_notes_path, params: { scope_kind: "entity", status: "active" }
    expect(response.body).to include("Invoices in euros.").and not_include("Pays at 45 days.", "Old convention")
    get agent_memory_notes_path, params: { category: "partner" }
    expect(response.body).to include("Pays at 45 days.").and not_include("Invoices in euros.")
  end

  it "lets anyone who may use the assistant read the list, and only those who manage the memory change it" do
    note
    sign_in reader

    get agent_memory_notes_path
    expect(response.body).to include("Invoices in euros.").and not_include("Add a note")
    expect { post agent_memory_notes_path, params: params }.not_to change(Agent::MemoryNote, :count)
  end

  it "edits, archives and deletes for good a note, each audited" do
    kept = note
    patch agent_memory_note_path(kept), params: { agent_memory_note: { scope_kind: "entity", text: "Invoices in euros and in dollars.", category: "convention" } }
    expect(kept.reload.text).to eq("Invoices in euros and in dollars.")

    post archive_agent_memory_note_path(kept)
    expect(kept.reload.status).to eq("archived")

    expect { delete agent_memory_note_path(kept) }.to change(Agent::MemoryNote, :count).by(-1)
    expect(Accounting::AuditLog.where(action: "memory_note_delete")).to exist
    expect(ActiveRecord::Base.connection.select_value("SELECT count(*) FROM agent_memory_notes WHERE id = #{kept.id}")).to eq(0)
  end

  it "refuses a note of more than 500 characters and one about an object that is not of the entity" do
    post agent_memory_notes_path, params: { agent_memory_note: { scope_kind: "entity", text: "x" * 501, category: "other" } }
    expect(response).to have_http_status(:unprocessable_content)
    post agent_memory_notes_path, params: { agent_memory_note: { scope_kind: "partner", partner_id: 0, text: "x", category: "other" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "does not show nor change the note of another entity" do
    foreign = ActsAsTenant.with_tenant(create(:entity)) { Agent::MemoryNote.create!(scope_kind: "entity", text: "FOREIGN note", category: "other", author: create(:user)) }

    get agent_memory_notes_path
    expect(response.body).not_to include("FOREIGN note")
    get edit_agent_memory_note_path(foreign)
    expect(response).to have_http_status(:not_found)
  end

  it "exports every note with its author, as a file" do
    note

    get export_agent_memory_notes_path

    expect(JSON.parse(response.body)["notes"].first).to include("text" => "Invoices in euros.", "author" => "Julie Martin", "status" => "active")
  end

  it "suggests archiving a note not used for a year" do
    note(text: "Forgotten note").tap { |n| n.update_columns(created_at: 13.months.ago) }

    get agent_memory_notes_path

    expect(response.body).to include("Not used for a year", "Forgotten note")
  end

  it "shows the notes of a partner on its page, and a way to add one" do
    note(scope_kind: "partner", scope_id: partner.id, text: "Pays at 45 days.")

    get accounting_partner_path(partner)

    expect(response.body).to include("Notes (memory of the file)", "Pays at 45 days.", "Add a note")
  end

  describe "remembering what the assistant said" do
    let(:conversation) { Agent::Conversation.create!(user: accountant, title: "t") }
    let(:message) { conversation.messages.create!(role: "assistant", content: "The customer pays at 45 days [[ref:partner:1]].", status: "complete") }

    it "opens the form filled with the words of the answer, markers out, to cut and correct" do
      get new_agent_memory_note_path(message_id: message.id)

      expect(response.body).to include("The customer pays at 45 days .").or include("The customer pays at 45 days")
      expect(response.body).not_to include("[[ref:")
    end

    it "does not give the words of someone else's answer" do
      other = Agent::Conversation.create!(user: owner, title: "x").messages.create!(role: "assistant", content: "SECRET answer", status: "complete")

      get new_agent_memory_note_path(message_id: other.id)

      expect(response.body).not_to include("SECRET answer")
    end
  end

  describe "a note the assistant proposed" do
    let(:conversation) { Agent::Conversation.create!(user: accountant, title: "t") }
    let(:context) { Agent::Context.build(user: accountant, entity: entity, locale: :en) }
    let(:proposal) do
      normalized = Agent::Proposals::Note.call({ "scope_kind" => "partner", "object_id" => partner.id, "text" => "Always asks for a purchase order.", "category" => "convention" }, context: context).normalized
      Agent::Proposal.create!(user: accountant, conversation: conversation, kind: "note", payload: normalized.to_json)
    end

    it "keeps nothing until the person confirms: the proposal alone is not a note" do
      expect { proposal }.not_to change(Agent::MemoryNote, :count)
    end

    it "is kept when the person says so, as a note of a proposal, with their name as the author" do
      expect { post accept_agent_proposal_path(proposal) }.to change(Agent::MemoryNote, :count).by(1)

      expect(Agent::MemoryNote.last).to have_attributes(text: "Always asks for a purchase order.", source: "proposal", proposal_id: proposal.id, author_id: accountant.id, scope_id: partner.id)
      expect(proposal.reload).to have_attributes(status: "created", result_type: "Agent::MemoryNote")
    end

    it "is refused to a person who does not manage the memory" do
      assistant = create(:user)
      create(:user_entity, :assistant, user: assistant, entity: entity)
      mine = Agent::Proposal.create!(user: assistant, conversation: conversation, kind: "note", payload: proposal.payload)
      sign_in assistant

      expect { post accept_agent_proposal_path(mine) }.not_to change(Agent::MemoryNote, :count)
      expect(flash[:alert]).to include("manages the memory")
    end

    it "opens the form filled with the proposal to correct it, and records the correction" do
      get modify_agent_proposal_path(proposal)
      expect(response).to redirect_to(new_agent_memory_note_path(proposal_id: proposal.id))

      post agent_memory_notes_path, params: { proposal_id: proposal.id, agent_memory_note: { scope_kind: "partner", partner_id: partner.id, text: "Always asks for a signed purchase order.", category: "convention" } }

      expect(proposal.reload).to have_attributes(status: "created", outcome: "modified", changed_fields: [ "text" ])
      expect(Agent::MemoryNote.last).to have_attributes(source: "proposal", text: "Always asks for a signed purchase order.")
    end
  end

  describe "the erasure of a person (A04)" do
    let(:subject_partner) { create(:partner, :customer, name: "Jean Dupuis", vat_number: nil, is_natural_person: true) }

    before { sign_in owner }

    it "finds the notes, the summaries, the proposals and the readings that name a person, exports them and erases them" do
      note(scope_kind: "partner", scope_id: subject_partner.id, text: "Pays late.")
      note(text: "Jean Dupuis asked for a copy.")
      keep = note(text: "Unrelated.")
      Agent::Digest.create!(user: accountant, kind: "scheduled", local_date: Date.current, payload: { "sections" => [ { "title" => "Receivables", "items" => [ { "detail" => "Jean Dupuis 100" } ] } ], "snapshot" => {} }.to_json)
      Agent::Proposal.create!(user: accountant, kind: "task", payload: { "kind" => "task", "title" => "Call Jean Dupuis" }.to_json)
      Agent::DocumentExtraction.create!(document: create(:document), requested_by: accountant, engine: "agent_text", payload: { "fields" => { "supplier_name" => { "value" => "Jean Dupuis" } } }.to_json)

      post agent_subject_requests_path, params: { name: "Jean Dupuis", operation: "search" }
      expect(response.body).to include("2 notes", "1 summary", "1 proposal", "1 reading of a document")

      post agent_subject_requests_path, params: { name: "Jean Dupuis", operation: "export", reason: "Access request" }
      export = JSON.parse(response.body)
      expect(export["notes"].size).to eq(2)
      expect(export["summaries"].size + export["proposals"].size + export["document_readings"].size).to eq(3)

      post agent_subject_requests_path, params: { name: "Jean Dupuis", operation: "erase", reason: "Erasure request" }

      expect(Agent::MemoryNote.all).to contain_exactly(keep)
      expect([ Agent::Digest.count, Agent::Proposal.count, Agent::DocumentExtraction.count ]).to eq([ 0, 0, 0 ])
    end
  end
end
