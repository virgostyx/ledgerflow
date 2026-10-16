require 'rails_helper'

# B02c, the client's side of the questions: read through the scope of the right, answered by type, once, with an untrusted text that is cleaned; nothing of the books changes.
RSpec.describe 'Portal questions', type: :request do
  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user) }
  let(:other)  { create(:portal_user) }
  let(:staff)  { create(:user) }

  def grant(user = person, capabilities: %w[questions.answer documents.upload], entity_id: entity.id)
    Portal::Grant.create!(portal_user: user, entity_id: entity_id, role: 'director', capabilities: capabilities)
  end

  def sign_in!(user = person)
    post '/session', params: { email: user.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }
  end

  def question(type: 'text', for_entity: entity, choices: [], **attrs)
    Portal::Question.create!({ entity_id: for_entity.id, task_id: 1, title: 'Is this professional?', answer_type: type, choices: choices, asked_at: Time.current, asked_by_id: staff.id,
                               context: { 'date' => '2026-03-04', 'label' => 'ACME Supplies', 'amount' => '-80.0', 'currency' => 'EUR' } }.merge(attrs))
  end

  let(:choices) { [ { 'key' => 'yes', 'label' => 'Yes' }, { 'key' => 'no', 'label' => 'No' }, { 'key' => 'part', 'label' => 'Partly' } ] }

  before { host! Rails.configuration.x.portal_host }

  describe 'reading' do
    it 'lists the open questions of the companies where the person may answer, with the limited context' do
      grant
      question
      sign_in!
      get '/questions'
      expect(response.body).to include('Is this professional?')
      get "/questions/#{Portal::Question.sole.token}"
      expect(response.body).to include('ACME Supplies', '2026-03-04')
    end

    it 'shows nothing without the right to answer, nor for a company that turned the feature off, nor the questions of another person or company' do
      grant(capabilities: %w[publications.view])
      question
      sign_in!
      get '/questions'
      expect(response.body).not_to include('Is this professional?')

      person.grants.destroy_all
      grant
      entity.update!(features: { 'b02c' => false })
      get '/questions'
      expect(response.body).not_to include('Is this professional?')

      entity.update!(features: { 'b02c' => true })
      question(portal_user: other, title: 'For someone else')
      question(for_entity: create(:entity), title: 'Foreign company')
      get '/questions'
      expect(response.body).not_to include('For someone else', 'Foreign company')
    end

    it 'speaks the language of the person' do
      grant
      question
      person.update!(locale: 'fr')
      sign_in!
      get '/questions'
      expect(response.body).to include('Répondre')
      person.update!(locale: 'nl')
      get '/questions'
      expect(response.body).to include('Antwoorden')
    end

    it 'answers 404 for the question of another company or person' do
      grant
      foreign = question(for_entity: create(:entity))
      sign_in!
      get "/questions/#{foreign.token}"
      expect(response).to have_http_status(:not_found)
      post "/questions/#{foreign.token}/answer", params: { body: 'x' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'answering by type' do
    before do
      grant
      sign_in!
    end

    def answer(q, **params) = post("/questions/#{q.token}/answer", params: params)

    it 'takes a free text, cleaned' do
      q = question
      answer(q, body: "<script>alert(1)</script>It was a <b>client</b> lunch\u0007\n\n\n\nthanks")

      expect(response).to redirect_to('/questions')
      expect(q.reload).to be_answered
      body = q.answer.body
      expect(body).to eq("alert(1)It was a client lunch\n\nthanks")
      expect(body).not_to match(/<|\u0007/)
    end

    it 'limits the text' do
      q = question
      answer(q, body: 'a' * 9000)
      expect(q.reload.answer.body.length).to eq(Portal::Answer::MAX_BODY)
    end

    it 'takes one choice of a list, not another' do
      q = question(type: 'single', choices: choices)
      answer(q, choice: 'maybe')
      expect(response).to have_http_status(:unprocessable_content)
      expect(q.reload).to be_open

      answer(q, choice: 'part', body: '60 %')
      expect(q.reload.answer.value).to eq('choices' => [ 'part' ])
    end

    it 'takes several choices, all from the list' do
      q = question(type: 'multiple', choices: choices)
      answer(q, choices: %w[yes zzz])
      expect(response).to have_http_status(:unprocessable_content)
      answer(q, choices: %w[yes part])
      expect(q.reload.answer.value).to eq('choices' => %w[yes part])
    end

    it 'takes a yes or a no' do
      q = question(type: 'yes_no')
      answer(q, yes_no: 'perhaps')
      expect(response).to have_http_status(:unprocessable_content)
      answer(q, yes_no: 'no')
      expect(q.reload.answer.value).to eq('yes_no' => false)
    end

    it 'takes an amount with two decimals at most, comma or point' do
      q = question(type: 'amount')
      answer(q, amount: 'lots')
      expect(response).to have_http_status(:unprocessable_content)
      answer(q, amount: '12,50')
      expect(q.reload.answer.value).to eq('amount' => '12.5')
      expect(q.answer.value['amount']).not_to be_a(Float)
    end

    it 'takes a real date' do
      q = question(type: 'date')
      answer(q, date: '2026-02-30')
      expect(response).to have_http_status(:unprocessable_content)
      answer(q, date: '2026-02-28')
      expect(q.reload.answer.value).to eq('date' => '2026-02-28')
    end

    it 'asks for a document first when the answer is a file' do
      q = question(type: 'file')
      answer(q)
      expect(response).to have_http_status(:unprocessable_content)

      Portal::Upload.create!(entity_id: entity.id, portal_user: person, filename: 'a.pdf', byte_size: 1, sha256: 'a' * 64, chunk_size: 1, chunk_count: 1, status: 'received', question_id: q.id, expires_at: 1.day.from_now)
      answer(q)
      expect(q.reload).to be_answered
    end

    it 'takes only one answer' do
      q = question
      answer(q, body: 'first')
      answer(q, body: 'second')
      expect(q.reload.answer.body).to eq('first')
      expect(Portal::Answer.count).to eq(1)
    end

    it 'changes nothing in the books and is written in the activity of the portal' do
      q = question
      expect { answer(q, body: 'x') }.not_to change { Accounting::JournalEntry.unscoped.count }
      expect(Portal::Event.where(action: 'question_answered', target_token: q.token)).to exist
    end
  end

  describe 'sending a file for a question' do
    it 'ties the upload to the question' do
      grant
      q = question(type: 'file')
      sign_in!

      post '/uploads', params: { company: entity.id, filename: 'invoice.pdf', byte_size: 1000, sha256: 'a' * 64, question: q.token }, as: :json

      expect(response).to have_http_status(:created)
      expect(Portal::Upload.sole.question_id).to eq(q.id)
    end

    it 'refuses a question that is not the person\'s' do
      grant
      foreign = question(for_entity: create(:entity))
      sign_in!
      post '/uploads', params: { company: entity.id, filename: 'invoice.pdf', byte_size: 1000, sha256: 'a' * 64, question: foreign.token }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
