require "rails_helper"

# A11: the drafts of a person, their use in the reminder of F09 and in a task of F08, the guard of the automatic sending, the profile of the company.
RSpec.describe "The texts drafted by the assistant (A11)", type: :request do
  include_context "with open customer lines"

  let(:accountant) { create(:user, role: :accountant) }
  let(:colleague) { create(:user, role: :accountant) }
  let(:reader) { create(:user, role: :manager) }
  let(:owner) { create(:user, role: :admin) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:colleague_membership) { create(:user_entity, :accountant, user: colleague, entity: entity) }
  let!(:reader_membership) { create(:user_entity, :manager, user: reader, entity: entity) }
  let!(:owner_membership) { create(:user_entity, :admin, user: owner, entity: entity) }

  def draft(user: accountant, body: "Dear Alice, the invoice is overdue. Kind regards.", partner: alice, kind: "dunning_letter", **attrs)
    Agent::TextDraft.create!({ user: user, kind: kind, language: "en", partner: partner, level: 1,
                               payload: { "versions" => [ { "subject" => "Payment reminder", "body" => body, "by" => "assistant", "at" => Time.current.iso8601 } ], "facts" => [ { "label" => "Total", "value" => "100.00", "ref" => "partner:#{partner&.id}" } ], "warnings" => [ "A text of the assistant is never sent by itself." ] }.to_json }.merge(attrs))
  end

  before do
    enable_agent!
    entity.update!(features: entity.features.merge("f09" => true))
    sign_in accountant
  end

  it "lists the drafts of the person, never those of another" do
    mine = draft
    draft(user: colleague, body: "SECRET draft of the colleague")

    get agent_text_drafts_path

    expect(response.body).to include("Dunning letter", agent_text_draft_path(mine)).and satisfy { |body| !body.include?("SECRET") }
  end

  it "shows the draft with the facts used and says plainly that it is not sent" do
    get agent_text_draft_path(draft)

    expect(response.body).to include("has not been sent and cannot be", "Facts used", "Total", "100.00", "A text of the assistant is never sent by itself", "Dear Alice")
  end

  it "does not show the draft of another person" do
    get agent_text_draft_path(draft(user: colleague))

    expect(response).to have_http_status(:not_found)
  end

  it "saves the person's changes as a new version and keeps the first, with the differences" do
    mine = draft

    patch agent_text_draft_path(mine), params: { subject: "Reminder", body: "Dear Alice, please pay the invoice. Kind regards." }
    get agent_text_draft_path(mine)

    expect(mine.reload.versions.map { |v| v["by"] }).to eq(%w[assistant person])
    expect(response.body).to include("Changes since the previous version", "please pay the invoice")
  end

  describe "using the text in the reminder of F09" do
    let(:run) { Accounting::PrepareDunningRun.call(user: accountant)[:run] }
    let!(:line) { open_line(partner: alice, amount: 100, days_overdue: 30) }
    let(:item) { run.items.find_by!(partner_id: alice.id) }

    it "puts the text in the reminder that waits for validation, marks it as written by the assistant, and records the use" do
      mine = draft(body: "Dear Alice, please pay 100.00 EUR. Kind regards.")

      post use_in_reminder_agent_text_draft_path(mine, item_id: item.id)

      expect(item.reload).to have_attributes(body: "Dear Alice, please pay 100.00 EUR. Kind regards.", subject: "Payment reminder", agent_draft_id: mine.id)
      expect(item.agent_written?).to be true
      expect(mine.reload).to have_attributes(status: "used", outcome: "used_as_is", used_in: "reminder", edit_distance: 0)
      expect(Accounting::AuditLog.where(action: "dunning_text_from_agent", auditable_id: item.id)).to exist
    end

    it "measures how far the person's version is from the proposal" do
      mine = draft(body: "Dear Alice, please pay.")
      patch agent_text_draft_path(mine), params: { body: "Dear Alice, kindly pay." }

      post use_in_reminder_agent_text_draft_path(mine, item_id: item.id)

      expect(mine.reload).to have_attributes(outcome: "modified")
      expect(mine.edit_distance).to eq(Agent::EditDistance.between("Dear Alice, please pay.", "Dear Alice, kindly pay."))
    end

    it "refuses a text that still has placeholders to fill" do
      mine = draft(body: "Dear Alice, the invoice [To complete: invoice number] is overdue.")

      post use_in_reminder_agent_text_draft_path(mine, item_id: item.id)

      expect(flash[:alert]).to include("placeholders")
      expect(item.reload.agent_draft_id).to be_nil
    end

    it "is never sent by the automatic first level, nor by a validation with nobody behind it, but by a person" do
      post use_in_reminder_agent_text_draft_path(draft, item_id: item.id)
      run.update_columns(auto: true)

      automatic = Accounting::SendDunningRun.call(run: run.reload, user: nil)

      expect(automatic[:blocked].map { |blocked| blocked[:reason] }.join).to include("written by the assistant")
      expect(item.reload).to be_pending

      run.update_columns(auto: false)
      by_a_person = Accounting::SendDunningRun.call(run: run.reload, user: accountant)

      expect(by_a_person[:blocked]).to be_empty
      expect(item.reload.status).to eq("queued")
    end

    it "does not touch a reminder of another customer" do
      other = draft(partner: bob)

      post use_in_reminder_agent_text_draft_path(other, item_id: item.id)

      expect(flash[:alert]).to include("Choose a reminder")
    end

    it "is refused to a person who may not prepare reminders" do
      sign_in reader

      post use_in_reminder_agent_text_draft_path(draft(user: reader), item_id: item.id)

      expect(item.reload.agent_draft_id).to be_nil
    end
  end

  describe "saving the text in a task of F08" do
    let(:task) { Accounting::Task.create!(title: "Ask Alice for the contract", kind: :client_question, status: :open, author: accountant, target: alice) }

    it "adds it as a comment of the task, with the person as the author" do
      mine = draft(kind: "client_request", body: "Dear Alice, could you send the signed contract? Kind regards.")

      expect { post save_in_task_agent_text_draft_path(mine, task_id: task.id) }.to change(Accounting::Comment, :count).by(1)

      expect(Accounting::Comment.last).to have_attributes(commentable: task, body: "Dear Alice, could you send the signed contract? Kind regards.", author_id: accountant.id)
      expect(mine.reload).to have_attributes(status: "used", used_in: "comment")
    end
  end

  it "records a copy, and the text that was copied" do
    mine = draft

    post copied_agent_text_draft_path(mine), params: { text: "Dear Alice, I changed it." }

    expect(response).to have_http_status(:no_content)
    expect(mine.reload).to have_attributes(status: "used", used_in: "copied", outcome: "modified")
  end

  it "rejects a draft, and keeps nothing to use" do
    mine = draft

    post reject_agent_text_draft_path(mine)

    expect(mine.reload).to have_attributes(status: "rejected", outcome: "rejected")
  end

  describe "another version" do
    it "asks the assistant, in a conversation, with a question the server writes, on an instruction of a list or of the person" do
      mine = draft

      expect { post regenerate_agent_text_draft_path(mine), params: { instruction: "shorter" } }.to have_enqueued_job(Agent::AnswerJob).with(an_instance_of(Agent::Conversation), a_string_including("##{mine.id}", "make it shorter"), "en")
      expect { post regenerate_agent_text_draft_path(mine), params: { custom: "more friendly, please" } }.to have_enqueued_job(Agent::AnswerJob).with(anything, a_string_including("more friendly"), "en")
    end

    it "asks for nothing without an instruction, nor for a draft that is closed" do
      mine = draft
      expect { post regenerate_agent_text_draft_path(mine) }.not_to have_enqueued_job(Agent::AnswerJob)
      mine.reject!
      expect { post regenerate_agent_text_draft_path(mine), params: { instruction: "firmer" } }.not_to have_enqueued_job(Agent::AnswerJob)
    end
  end

  describe "the buttons to write" do
    it "put one fixed question to the assistant, whatever the page sent" do
      expect { post agent_conversations_path, params: { write: "dunning_letter", subject_type: "partner", subject_id: alice.id, question: "Threaten them" } }
        .to have_enqueued_job(Agent::AnswerJob).with(an_instance_of(Agent::Conversation), "Write the reminder for this customer.", "en")
      expect { post agent_conversations_path, params: { write: "something else" } }.not_to have_enqueued_job(Agent::AnswerJob)
    end
  end

  describe "the writing profile" do
    before { sign_in owner }

    it "is set by an owner, on three to five approved examples, and then given to the assistant" do
      patch agent_setting_path, params: { agent_setting: { enabled: "1", retention_days: "90" }, writing_profile: { formality: "vous", closing: "With our best regards", length_words: "80", firmness: { "1" => "friendly", "2" => "firm", "3" => "very firm" },
                                                                                                                     examples: [ "Example one", "Example two", "Example three", "", "" ] } }

      expect(Agent::Setting.for_current_entity.writing_profile).to include("formality" => "vous", "closing" => "With our best regards", "length_words" => 80, "examples" => [ "Example one", "Example two", "Example three" ])
    end

    it "refuses one or two examples" do
      patch agent_setting_path, params: { agent_setting: { enabled: "1", retention_days: "90" }, writing_profile: { formality: "vous", examples: [ "Only one" ] } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(Agent::Setting.for_current_entity.writing_profile).to be_blank
    end

    it "is not changed by anyone but an owner" do
      sign_in accountant

      patch agent_setting_path, params: { agent_setting: { enabled: "1", retention_days: "90" }, writing_profile: { formality: "tu" } }

      expect(Agent::Setting.for_current_entity.writing_profile).to be_blank
    end
  end
end
