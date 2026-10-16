require 'rails_helper'

# B02a: what a person from outside sees of the firm's publications, through the scope of their grants: nothing else, nothing outside, nothing withdrawn.
RSpec.describe 'Portal publications', type: :request do
  let(:entity)  { create(:entity) }
  let(:staff)   { create(:user) }
  let(:person)  { create(:portal_user) }
  let(:pdf_data) { Prawn::Document.new { |d| d.text 'Balance sheet' }.render }
  let(:pdf)     { { filename: 'balance.pdf', content_type: 'application/pdf', data: pdf_data } }

  def publish(for_entity: entity, **args)
    PortalAdmin::Publish.call(entity: for_entity, kind: 'monthly_report', title: 'March 2026', files: [ pdf ], by: staff, **args)[:publication]
  end

  def grant(capabilities: %w[publications.view], entity_id: entity.id, **attrs)
    Portal::Grant.create!(portal_user: person, entity_id: entity_id, role: 'director', capabilities: capabilities, **attrs)
  end

  def sign_in!
    post '/session', params: { email: person.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(person.totp_secret) }
  end

  before { host! Rails.configuration.x.portal_host }

  describe 'the list' do
    it 'shows the publications of the companies where the grant allows it' do
      grant
      publish
      sign_in!
      get '/publications'
      expect(response.body).to include('March 2026')
    end

    it 'shows nothing without the right to see publications' do
      grant(capabilities: %w[documents.upload])
      publish
      sign_in!
      get '/publications'
      expect(response.body).not_to include('March 2026')
    end

    it 'does not show another company, a withdrawn, a replaced or an expired publication, nor one for someone else' do
      grant
      other_company = publish(for_entity: create(:entity))
      withdrawn = publish.tap { |p| PortalAdmin::Withdraw.call(publication: p, by: staff, reason: 'x') }
      old = publish
      newer = publish(replaces: old, title: 'Newest')
      expired = publish(expires_at: 1.minute.ago)
      private_one = publish(title: 'Private', recipients: [ create(:portal_user) ])
      sign_in!
      get '/publications'

      body = response.body
      expect(body).to include('Newest')
      expect([ other_company, withdrawn, old, expired, private_one ].map(&:token)).to all(satisfy { |t| !body.include?(t) })
      expect(body).not_to include('Private')
      expect(newer).to be_persisted
    end

    it 'stops at once when the right is revoked' do
      g = grant
      publish
      sign_in!
      g.update!(revoked_at: Time.current)
      get '/publications'
      expect(response.body).not_to include('March 2026')
    end

    it 'stops when the right has expired during the session' do
      g = grant(expires_at: 10.minutes.from_now)
      publication = publish
      sign_in!
      get "/publications/#{publication.token}"
      expect(response).to have_http_status(:ok)
      travel_to(11.minutes.from_now) do
        get "/publications/#{publication.token}"
        expect(response).to have_http_status(:not_found)
      end
      expect(g).to be_persisted
    end
  end

  describe 'one publication' do
    it 'shows its title, message, version and files with their SHA-256' do
      grant
      publication = publish(message: 'Hello, here is March.')
      sign_in!
      get "/publications/#{publication.token}"

      expect(response.body).to include('March 2026').and include('Hello, here is March.').and include('balance.pdf').and include(publication.files.first.sha256)
      expect(Portal::Event.where(action: 'publication_viewed', target_token: publication.token)).to exist
    end

    it 'answers 404 to a publication outside the scope, without telling why' do
      grant
      foreign = publish(for_entity: create(:entity))
      withdrawn = publish.tap { |p| PortalAdmin::Withdraw.call(publication: p, by: staff, reason: 'x') }
      sign_in!

      [ foreign, withdrawn ].each do |publication|
        get "/publications/#{publication.token}"
        expect(response).to have_http_status(:not_found)
      end
      get '/publications/guess'
      expect(response).to have_http_status(:not_found)
      expect(Portal::Event.where(action: 'out_of_scope_attempt', target_token: 'guess')).to exist
    end

    it 'says clearly that a withdrawn publication is no longer there' do
      grant
      publication = publish
      sign_in!
      PortalAdmin::Withdraw.call(publication: publication, by: staff, reason: 'sent by mistake')
      get "/publications/#{publication.token}"
      expect(response).to have_http_status(:not_found)
      expect(response.body).to match(/no longer available/i)
      expect(response.body).not_to include('sent by mistake')
    end
  end

  describe 'downloading' do
    def link_of(publication)
      get "/publications/#{publication.token}"
      response.body[%r{href="(/downloads/[^"]+)"}, 1]
    end

    it 'goes through a link signed for five minutes, for this person only' do
      grant
      publication = publish(watermark: false)
      sign_in!
      link = link_of(publication)
      expect(link).to be_present

      get link
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(pdf_data)
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(Portal::Event.where(action: 'publication_downloaded')).to exist
    end

    it 'expires after five minutes' do
      grant
      publication = publish(watermark: false)
      sign_in!
      link = link_of(publication)
      travel_to(6.minutes.from_now) do
        get link
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'is not usable by someone else' do
      grant
      publication = publish(watermark: false)
      sign_in!
      link = link_of(publication)
      delete '/session'

      other = create(:portal_user)
      Portal::Grant.create!(portal_user: other, entity_id: entity.id, role: 'director', capabilities: %w[publications.view])
      post '/session', params: { email: other.email, password: 'correct horse battery' }
      post '/second_factor/challenge', params: { code: Totp.code(other.totp_secret) }
      get link
      expect(response).to have_http_status(:not_found)
    end

    it 'is refused when the right was revoked after the link was given' do
      g = grant
      publication = publish(watermark: false)
      sign_in!
      link = link_of(publication)
      g.update!(revoked_at: Time.current)
      get link
      expect(response).to have_http_status(:not_found)
    end

    it 'checks the SHA-256 and refuses a file that no longer matches' do
      grant
      publication = publish(watermark: false)
      sign_in!
      link = link_of(publication)
      tamper(:portal_publication_files) { Portal::PublicationFile.where(id: publication.files.first.id).update_all(content: Prawn::Document.new { |d| d.text 'Altered' }.render) }

      get link
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).not_to include('Altered')
      expect(Portal::Event.where(action: 'download_integrity_failed')).to exist
    end

    it 'puts the name of the person and the date across a PDF when the publication asks for it' do
      grant
      publication = publish(watermark: true)
      sign_in!
      get link_of(publication)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to eq(pdf_data)
      expect(response.body.b).to include('Viewed by Client Person')
    end
  end
end
