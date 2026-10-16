require 'rails_helper'

# B02b, criteria 1 and 2: an upload cut in the middle resumes at the exact place and ends as the same file (SHA-256), whatever the network loses, repeats or reorders;
# a chunk or a session replayed creates nothing twice.
RSpec.describe 'Portal uploads in chunks', type: :request do
  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user) }
  let(:data)   { Random.new(7).bytes(2_500_000) } # three chunks of 1 MB, the last one partial
  let(:sha)    { Digest::SHA256.hexdigest(data) }

  def grant(capabilities: %w[documents.upload], entity_id: entity.id)
    Portal::Grant.create!(portal_user: person, entity_id: entity_id, role: 'collaborator', capabilities: capabilities)
  end

  def sign_in!
    post '/session', params: { email: person.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(person.totp_secret) }
  end

  def start(overrides = {})
    post '/uploads', params: { company: entity.id, filename: 'invoice.pdf', byte_size: data.bytesize, sha256: sha, content_type: 'application/pdf' }.merge(overrides), as: :json
  end

  def put_chunk(token, position, bytes: data.byteslice(position * Portal::Upload::CHUNK_SIZE, Portal::Upload::CHUNK_SIZE), sha256: Digest::SHA256.hexdigest(bytes))
    put "/uploads/#{token}/chunks/#{position}", params: bytes, headers: { 'CONTENT_TYPE' => 'application/octet-stream', 'X-Chunk-SHA256' => sha256 }
  end

  before { host! Rails.configuration.x.portal_host }

  describe 'the page and the script' do
    it 'shows the company the documents are sent to' do
      grant
      sign_in!
      get '/uploads/new'
      expect(response.body).to include(entity.name, 'Choose a file')
    end

    it 'tells a script that its session is over with a 401, instead of a page to sign in' do
      get '/uploads/some-token', headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'serves the manifest and the service worker to anyone (they hold nothing), the worker with the scope of the whole portal' do
      get '/manifest.webmanifest'
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/manifest+json')
      expect(JSON.parse(response.body)).to include('start_url' => '/', 'display' => 'standalone')

      get '/service-worker.js'
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/javascript')
      expect(response.headers['Service-Worker-Allowed']).to eq('/')
      expect(response.body).to include('PortalOutbox')
    end

    it 'loads nothing from anywhere but the portal: the CSP lets the worker and the manifest be its own' do
      get '/sign_in'
      csp = response.headers['Content-Security-Policy']
      expect(csp).to include("worker-src 'self'", "manifest-src 'self'")
      expect(csp).not_to match(%r{https?://|\*})
    end

    it 'says there is nothing to send for someone who has no right to' do
      grant(capabilities: %w[publications.view])
      sign_in!
      get '/uploads/new'
      expect(response.body).to include('cannot send documents')
    end
  end

  describe 'opening a session' do
    before { grant }

    it 'gives a token, the size of a chunk and an expiry in 48 hours' do
      sign_in!
      start
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include('chunk_size' => Portal::Upload::CHUNK_SIZE, 'chunk_count' => 3, 'received' => [], 'status' => 'receiving')
      expect(Portal::Upload.find_by(token: body['token']).expires_at).to be_within(1.minute).of(48.hours.from_now)
    end

    it 'refuses a person who has no right to upload' do
      person.grants.destroy_all
      grant(capabilities: %w[publications.view])
      sign_in!
      expect { start }.not_to change(Portal::Upload, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses a company where the feature is off' do
      entity.update!(features: { 'b02b' => false })
      sign_in!
      expect { start }.not_to change(Portal::Upload, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses a size or a checksum that makes no sense' do
      sign_in!
      start(byte_size: 0)
      expect(response).to have_http_status(:unprocessable_content)
      start(sha256: 'zz')
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'sending chunks' do
    before do
      grant
      sign_in!
      start
      @token = response.parsed_body['token']
    end

    it 'stores a chunk and says so' do
      put_chunk(@token, 0)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['received']).to eq([ 0 ])
    end

    it 'does nothing when the same chunk comes again' do
      put_chunk(@token, 1)
      expect { put_chunk(@token, 1) }.not_to change(Portal::UploadChunk, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'refuses a chunk whose checksum is not the one announced' do
      put_chunk(@token, 0, sha256: Digest::SHA256.hexdigest('other'))
      expect(response).to have_http_status(:unprocessable_content)
      expect(Portal::UploadChunk.count).to eq(0)
    end

    it 'refuses another content for a chunk already received' do
      put_chunk(@token, 0)
      put_chunk(@token, 0, bytes: 'x' * Portal::Upload::CHUNK_SIZE)
      expect(response).to have_http_status(:conflict)
    end

    it 'refuses a chunk of the wrong size, or beyond the end' do
      put_chunk(@token, 0, bytes: 'short')
      expect(response).to have_http_status(:unprocessable_content)
      put_chunk(@token, 3, bytes: 'x')
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'tells where to resume' do
      put_chunk(@token, 0)
      put_chunk(@token, 2)
      get "/uploads/#{@token}"
      expect(response.parsed_body).to include('received' => [ 0, 2 ], 'status' => 'receiving')
    end
  end

  describe 'completing' do
    before do
      grant
      sign_in!
      start
      @token = response.parsed_body['token']
    end

    it 'refuses while a chunk is missing, and says which' do
      put_chunk(@token, 0)
      post "/uploads/#{@token}/complete"
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['missing']).to eq([ 1, 2 ])
    end

    it 'gives a receipt once every chunk is there and the whole is the file announced' do
      3.times { |i| put_chunk(@token, i) }
      post "/uploads/#{@token}/complete"
      expect(response).to have_http_status(:ok)
      receipt = response.parsed_body
      expect(receipt).to include('status' => 'received', 'filename' => 'invoice.pdf', 'token' => @token)
      expect(receipt['sha256_start']).to eq(sha.first(12))
      expect(Portal::Upload.find_by(token: @token).bytes).to eq(data)
    end

    it 'gives the same receipt when asked again' do
      3.times { |i| put_chunk(@token, i) }
      post "/uploads/#{@token}/complete"
      first = response.parsed_body
      post "/uploads/#{@token}/complete"
      expect(response.parsed_body).to eq(first)
    end

    it 'refuses a whole that is not the file announced' do
      start(sha256: Digest::SHA256.hexdigest('another file'))
      token = response.parsed_body['token']
      3.times { |i| put_chunk(token, i) }
      post "/uploads/#{token}/complete"
      expect(response).to have_http_status(:unprocessable_content)
      expect(Portal::Upload.find_by(token: token).status).to eq('receiving')
    end

    it 'takes no chunk after the end' do
      3.times { |i| put_chunk(@token, i) }
      post "/uploads/#{@token}/complete"
      put_chunk(@token, 0, bytes: 'x' * Portal::Upload::CHUNK_SIZE)
      expect(response).to have_http_status(:conflict)
    end
  end

  describe 'the audit trail (criterion 11)' do
    it 'keeps each send in R18 with who sent it, and the refusals too' do
      grant
      sign_in!
      start
      token = response.parsed_body['token']
      3.times { |i| put_chunk(token, i) }
      post "/uploads/#{token}/complete"
      Rails.configuration.x.portal_uploads = Rails.configuration.x.portal_uploads.merge(files_per_day: 1)
      start
      expect(response).to have_http_status(:too_many_requests)
      Rails.configuration.x.portal_uploads = Rails.configuration.x.portal_uploads.merge(files_per_day: 200)

      PortalAdmin::MirrorEvents.call

      trail = ActsAsTenant.with_tenant(entity) { Accounting::AuditLog.where(actor_type: 'portal_user').order(:id).to_a }
      expect(trail.map(&:action)).to include('portal_upload_started', 'portal_upload_received', 'portal_upload_refused')
      received = trail.find { |row| row.action == 'portal_upload_received' }
      expect(received.payload).to include('email' => person.email, 'portal_user_id' => person.id, 'sha256' => sha, 'filename' => 'invoice.pdf')
    end
  end

  describe 'a bad network (criteria 1 and 2)' do
    it 'ends with the same file when chunks are lost, repeated and out of order, over several resumptions' do
      grant
      sign_in!
      start
      token = response.parsed_body['token']
      rng = Random.new(42)

      # first attempt: chunk 2 arrives, the answer to chunk 0 is lost (the client sends it again), then the connection drops
      put_chunk(token, 2)
      put_chunk(token, 0)
      put_chunk(token, 0)
      # the client comes back and asks where it stopped
      get "/uploads/#{token}"
      missing = (0...3).to_a - response.parsed_body['received']
      expect(missing).to eq([ 1 ])
      # and sends what is missing, with a few repeats of what it already sent
      (missing + [ 0, 2, 1 ]).shuffle(random: rng).each { |i| put_chunk(token, i) }
      post "/uploads/#{token}/complete"
      post "/uploads/#{token}/complete"

      upload = Portal::Upload.find_by(token: token)
      expect(Portal::Upload.count).to eq(1)
      expect(Portal::UploadChunk.count).to eq(3)
      expect(Digest::SHA256.hexdigest(upload.bytes)).to eq(sha)
    end
  end

  describe 'who may see a session' do
    it 'answers 404 for the session of someone else' do
      grant
      other = create(:portal_user)
      Portal::Grant.create!(portal_user: other, entity_id: entity.id, role: 'collaborator', capabilities: %w[documents.upload])
      theirs = Portal::Upload.create!(entity_id: entity.id, portal_user: other, filename: 'x.pdf', byte_size: 10, sha256: sha, chunk_size: Portal::Upload::CHUNK_SIZE, chunk_count: 1,
                                      expires_at: 48.hours.from_now)
      sign_in!
      get "/uploads/#{theirs.token}"
      expect(response).to have_http_status(:not_found)
      put_chunk(theirs.token, 0, bytes: 'x' * 10)
      expect(response).to have_http_status(:not_found)
      post "/uploads/#{theirs.token}/complete"
      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 once the right is gone' do
      grant
      sign_in!
      start
      token = response.parsed_body['token']
      person.grants.update_all(revoked_at: Time.current)
      get "/uploads/#{token}"
      expect(response).to have_http_status(:not_found)
    end

    it 'answers 410 for a session that expired' do
      grant
      sign_in!
      start
      token = response.parsed_body['token']
      Portal::Upload.find_by(token: token).update_columns(expires_at: 1.minute.ago)
      put_chunk(token, 0)
      expect(response).to have_http_status(:gone)
    end
  end
end
