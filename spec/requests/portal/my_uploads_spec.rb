require 'rails_helper'

# B02b, criteria 7 and 9: what a client sees of their sends (their own only, with the status they may know), and the quotas that stop abuse with a clear message.
RSpec.describe 'Portal uploads: my sends and quotas', type: :request do
  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user) }
  let(:other)  { create(:portal_user) }
  let(:sha)    { Digest::SHA256.hexdigest('x') }

  def grant(user = person, capabilities: %w[documents.upload])
    Portal::Grant.create!(portal_user: user, entity_id: entity.id, role: 'collaborator', capabilities: capabilities)
  end

  def sign_in!(user = person)
    post '/session', params: { email: user.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }
  end

  def upload_for(user, **attrs)
    Portal::Upload.create!({ entity_id: entity.id, portal_user: user, filename: 'a.pdf', byte_size: 10, sha256: sha, chunk_size: Portal::Upload::CHUNK_SIZE, chunk_count: 1,
                             expires_at: 48.hours.from_now }.merge(attrs))
  end

  def start(overrides = {})
    post '/uploads', params: { company: entity.id, filename: 'invoice.pdf', byte_size: 1000, sha256: sha, content_type: 'application/pdf' }.merge(overrides), as: :json
  end

  around do |example|
    previous = Rails.configuration.x.portal_uploads
    example.run
  ensure
    Rails.configuration.x.portal_uploads = previous
  end

  before { host! Rails.configuration.x.portal_host }

  describe 'the list' do
    it 'shows the sends of the person with their receipt and a status, and nobody else\'s' do
      grant
      grant(other)
      upload_for(person, filename: 'mine.pdf', status: 'received', received_at: Time.current)
      upload_for(other, filename: 'theirs.pdf', status: 'received', received_at: Time.current)
      sign_in!

      get '/uploads'

      expect(response.body).to include('mine.pdf', 'Received', sha.first(12))
      expect(response.body).not_to include('theirs.pdf')
    end

    it 'speaks the language of the client, not the books' do
      grant
      upload_for(person, filename: 'f0.pdf', status: 'accepted', progress: 'in_progress', received_at: Time.current)
      upload_for(person, filename: 'f1.pdf', status: 'to_complete', received_at: Time.current)
      upload_for(person, filename: 'f2.pdf', status: 'refused', refusal_reason: 'duplicate', received_at: Time.current)
      upload_for(person, filename: 'booked.pdf', status: 'accepted', progress: 'booked', received_at: Time.current)
      sign_in!

      get '/uploads'

      expect(response.body).to include('In progress', 'To complete', 'Refused', 'Booked', 'already sent')
      expect(response.body).not_to match(/journal|entry|account number|ledger/i)
    end

    it 'hides the sends of a company where the right is gone' do
      grant
      upload_for(person, filename: 'old.pdf', status: 'received', received_at: Time.current)
      person.grants.update_all(revoked_at: Time.current)
      sign_in!
      get '/uploads'
      expect(response.body).not_to include('old.pdf')
    end
  end

  describe 'quotas (criterion 9)' do
    before do
      grant
      sign_in!
    end

    it 'stops the 201st file of the day of a person, with a clear message' do
      Rails.configuration.x.portal_uploads = Rails.configuration.x.portal_uploads.merge(files_per_day: 2)
      2.times { start }
      expect(response).to have_http_status(:created)

      start

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['message']).to match(/daily limit of 2 files/)
    end

    it 'does not count the files of another person' do
      Rails.configuration.x.portal_uploads = Rails.configuration.x.portal_uploads.merge(files_per_day: 1)
      grant(other)
      upload_for(other)
      start
      expect(response).to have_http_status(:created)
    end

    it 'lets the day start again' do
      Rails.configuration.x.portal_uploads = Rails.configuration.x.portal_uploads.merge(files_per_day: 1)
      upload_for(person, created_at: 25.hours.ago)
      start
      expect(response).to have_http_status(:created)
    end

    it 'stops a company that would go over its volume of the month' do
      Rails.configuration.x.portal_uploads = Rails.configuration.x.portal_uploads.merge(bytes_per_month: 1500)
      start(byte_size: 1000)
      expect(response).to have_http_status(:created)

      start(byte_size: 1000)

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['message']).to match(/monthly volume/)
    end

    it 'refuses a file above 25 MB' do
      start(byte_size: 26.megabytes)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'refuses a batch of more than 20 pages' do
      start(batch_token: 'b', page_number: 1, page_count: 21)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
