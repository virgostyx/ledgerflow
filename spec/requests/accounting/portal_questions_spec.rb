require "rails_helper"

# B02c, firm side: ask a question about a bank line, a document or an entry, with the templates; see the answers; close a question. Right: portal.manage.
RSpec.describe "Portal questions (firm side)", type: :request do
  include_context "with entity"
  include DocumentFiles

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:person)     { create(:portal_user) }
  let!(:line)      { create(:bank_transaction, counterparty_name: "ACME Supplies") }

  before do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: "director", capabilities: %w[questions.answer])
    sign_in accountant
  end

  def ask(**params)
    post accounting_portal_questions_path, params: { title: "Is this professional?", answer_type: "single", choices: "yes|Yes|professional: expense\nno|No|private: current account", target_type: "Accounting::BankTransaction", target_id: line.id }.merge(params)
  end

  it "asks a question about a bank line, with choices and suggested treatments" do
    expect { ask }.to change(Portal::Question, :count).by(1)

    question = Portal::Question.sole
    expect(question.choices.map { |c| c["key"] }).to eq(%w[yes no])
    expect(question.context["label"]).to eq("ACME Supplies")
    expect(Accounting::QuestionSuggestion.count).to eq(2)
    expect(response).to redirect_to(accounting_portal_questions_path)
  end

  it "says why it cannot ask" do
    ask(title: "")
    follow_redirect!
    expect(response.body).to include("Write the question")
  end

  it "offers the templates in the language of the client, filled in the form" do
    get new_accounting_portal_question_path(template: "professional", language: "fr", target_type: "Accounting::BankTransaction", target_id: line.id)
    expect(response.body).to include("Cette dépense est-elle professionnelle ?", "En partie")
  end

  it "lists the questions, their state and their answers" do
    ask
    question = Portal::Question.sole
    Portal::Answer.create!(question: question, portal_user: person, entity_id: entity.id, value: { "choices" => [ "yes" ] }, body: "Client lunch", answered_at: Time.current)
    question.update!(status: "answered")

    get accounting_portal_questions_path

    expect(response.body).to include("Is this professional?", "answered", "Yes", "Client lunch", "ACME Supplies")
  end

  it "closes a question" do
    ask
    post close_accounting_portal_question_path(Portal::Question.sole)
    expect(Portal::Question.sole.status).to eq("closed")
    expect(Accounting::AuditLog.where(action: "portal_question_closed").count).to eq(1)
  end

  it "refuses a target of another company" do
    foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:bank_transaction) }
    expect { ask(target_id: foreign.id) }.not_to change(Portal::Question, :count)
  end

  it "does not show the questions of another company" do
    ActsAsTenant.with_tenant(create(:entity)) { }
    Portal::Question.create!(entity_id: create(:entity).id, task_id: 1, title: "Foreign one", answer_type: "text", asked_at: Time.current, asked_by_id: accountant.id)
    get accounting_portal_questions_path
    expect(response.body).not_to include("Foreign one")
  end

  it "is for those who manage the portal, and closed while the feature is off" do
    sign_in reader
    expect { ask }.not_to change(Portal::Question, :count)
    sign_in accountant
    entity.update!(features: { "b02c" => false })
    get accounting_portal_questions_path
    expect(response).to redirect_to(accounting_root_path)
  end
end
