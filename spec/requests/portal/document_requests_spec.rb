require 'rails_helper'

# B02b, "Pièces demandées" on the client's side: limited fields (never an IBAN), a document sent for a line, or an answer without a document from a list of reasons. Nothing is booked.
RSpec.describe 'Portal document requests', type: :request do
  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user) }
  let(:staff)  { create(:user) }

  def grant(user = person, capabilities: %w[documents.upload bank_lines.view questions.answer], entity_id: entity.id)
    Portal::Grant.create!(portal_user: user, entity_id: entity_id, role: 'director', capabilities: capabilities)
  end

  def sign_in!(user = person)
    post '/session', params: { email: user.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }
  end

  def request_for(for_entity = entity, label: 'ACME Supplies', amount: '-123.45')
    req = Portal::DocumentRequest.create!(entity_id: for_entity.id, requested_by: staff, message: 'Please send the invoices', due_on: Date.new(2026, 4, 15))
    req.lines.create!(entity_id: for_entity.id, bank_transaction_id: 1, line_date: Date.new(2026, 3, 4), label: label, amount: amount, currency: 'EUR')
  end

  before { host! Rails.configuration.x.portal_host }

  describe 'the list' do
    it 'shows the date, the label and the amount of each line asked for, and the message' do
      grant
      request_for
      sign_in!

      get '/document_requests'

      expect(response.body).to include('2026-03-04', 'ACME Supplies', '-123.45', 'Please send the invoices', '2026-04-15')
    end

    it 'shows nothing to someone who may not see bank lines' do
      grant(capabilities: %w[documents.upload])
      request_for
      sign_in!
      get '/document_requests'
      expect(response.body).not_to include('ACME Supplies')
    end

    it 'shows nothing when the company hides its bank lines' do
      grant
      request_for
      entity.update!(portal_show_bank_lines: false)
      sign_in!
      get '/document_requests'
      expect(response.body).not_to include('ACME Supplies')
    end

    it 'does not show the lines of a company where the person has no right, nor the withdrawn ones with their reason hidden' do
      grant
      request_for(create(:entity), label: 'Somebody else')
      line = request_for(label: 'Withdrawn one')
      line.update!(state: 'withdrawn', withdrawn_reason: 'This line was justified by your accountant.')
      sign_in!

      get '/document_requests'

      expect(response.body).not_to include('Somebody else')
      expect(response.body).to include('justified by your accountant')
    end

    it 'never speaks of the books' do
      grant
      request_for
      sign_in!
      get '/document_requests'
      expect(response.body).not_to match(/IBAN|journal entry|ledger/i)
    end
  end

  describe 'answering without a document' do
    before do
      grant
      sign_in!
    end

    it 'keeps the reason and the note, and changes nothing in the books' do
      line = request_for

      post "/document_request_lines/#{line.token}/answer", params: { reason: 'personal', note: 'my lunch' }

      expect(response).to redirect_to('/document_requests')
      expect(line.reload).to have_attributes(state: 'explained', answer_reason: 'personal', answer_note: 'my lunch', answered_by_id: person.id)
      expect(Accounting::JournalEntry.unscoped.count).to eq(0)
    end

    it 'refuses a reason that is not on the list' do
      line = request_for
      post "/document_request_lines/#{line.token}/answer", params: { reason: 'because' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(line.reload.state).to eq('open')
    end

    it 'asks for a note when the reason is "other"' do
      line = request_for
      post "/document_request_lines/#{line.token}/answer", params: { reason: 'other', note: '' }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'answers only once' do
      line = request_for
      post "/document_request_lines/#{line.token}/answer", params: { reason: 'lost' }
      post "/document_request_lines/#{line.token}/answer", params: { reason: 'personal' }
      expect(line.reload.answer_reason).to eq('lost')
    end

    it 'needs the right to answer' do
      person.grants.update_all(capabilities: %w[bank_lines.view documents.upload])
      line = request_for
      post "/document_request_lines/#{line.token}/answer", params: { reason: 'personal' }
      expect(response).to have_http_status(:not_found)
      expect(line.reload.state).to eq('open')
    end

    it 'answers 404 for a line of another company' do
      line = request_for(create(:entity))
      post "/document_request_lines/#{line.token}/answer", params: { reason: 'personal' }
      expect(response).to have_http_status(:not_found)
    end

    it 'records the answer in the activity of the portal' do
      line = request_for
      post "/document_request_lines/#{line.token}/answer", params: { reason: 'personal' }
      expect(Portal::Event.where(action: 'document_request_answered', target_token: line.token)).to exist
    end
  end

  describe 'sending a document for a line' do
    before do
      grant
      sign_in!
    end

    def start(line, overrides = {})
      post '/uploads', params: { company: entity.id, filename: 'invoice.pdf', byte_size: 1000, sha256: 'a' * 64, request_line: line.token }.merge(overrides), as: :json
    end

    it 'ties the upload to the line' do
      line = request_for
      start(line)
      expect(response).to have_http_status(:created)
      expect(Portal::Upload.sole.request_line_id).to eq(line.id)
    end

    it 'refuses a line that is not open any more, or not the person\'s to see' do
      done = request_for.tap { |l| l.update!(state: 'withdrawn') }
      start(done)
      expect(response).to have_http_status(:not_found)

      foreign = request_for(create(:entity))
      start(foreign)
      expect(response).to have_http_status(:not_found)
      expect(Portal::Upload.count).to eq(0)
    end

    it 'shows the line on the sending page' do
      line = request_for
      get "/uploads/new?line=#{line.token}"
      expect(response.body).to include('ACME Supplies', '-123.45')
    end
  end
end
