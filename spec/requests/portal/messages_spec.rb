require 'rails_helper'

# B02c: the thread of messages of a company, from the client's side: write, read the answers of the firm, send a document into the thread; scoped, cleaned, limited.
RSpec.describe 'Portal messages', type: :request do
  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user, full_name: 'Jane Client') }
  let(:other)  { create(:portal_user, full_name: 'Joe Colleague') }
  let(:staff)  { create(:user, full_name: 'Alice Accountant') }

  def grant(user = person, capabilities: %w[messages.use documents.upload], entity_id: entity.id)
    Portal::Grant.create!(portal_user: user, entity_id: entity_id, role: 'collaborator', capabilities: capabilities)
  end

  def sign_in!(user = person)
    post '/session', params: { email: user.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }
  end

  def thread_of(for_entity = entity) = Portal::MessageThread.of(for_entity.id)

  before { host! Rails.configuration.x.portal_host }

  it 'shows the thread of the company: the messages of the colleagues and of the firm, with the note that a message is no instruction' do
    grant
    grant(other)
    thread = thread_of
    thread.messages.create!(entity_id: entity.id, author_kind: 'client', portal_user: other, body: 'Hello from Joe')
    thread.messages.create!(entity_id: entity.id, author_kind: 'firm', user_id: staff.id, body: 'Hello from the firm')
    sign_in!

    get '/messages'

    expect(response.body).to include('Hello from Joe', 'Joe Colleague', 'Hello from the firm', 'not an accounting instruction')
  end

  it 'keeps the threads of two companies apart' do
    grant
    thread_of(create(:entity)).messages.create!(entity_id: Portal::MessageThread.last.entity_id, author_kind: 'firm', user_id: staff.id, body: 'Not for you')
    sign_in!
    get '/messages'
    expect(response.body).not_to include('Not for you')
  end

  it 'writes a message, cleaned and limited' do
    grant
    sign_in!

    post '/messages', params: { company: entity.id, body: "Hello <script>x()</script> there\u0007" }

    message = Portal::Message.sole
    expect(message).to have_attributes(author_kind: 'client', portal_user_id: person.id, entity_id: entity.id, body: 'Hello x() there')
    post '/messages', params: { company: entity.id, body: 'a' * 5000 }
    expect(Portal::Message.order(:id).last.body.length).to eq(Portal::Message::MAX_BODY)
  end

  it 'refuses an empty message, and a company where the person has no right to write' do
    grant
    sign_in!
    post '/messages', params: { company: entity.id, body: '   ' }
    expect(response).to have_http_status(:unprocessable_content)

    post '/messages', params: { company: create(:entity).id, body: 'hi' }
    expect(response).to have_http_status(:not_found)
    expect(Portal::Message.count).to eq(0)
  end

  it 'needs the right to use messages' do
    grant(capabilities: %w[publications.view])
    sign_in!
    post '/messages', params: { company: entity.id, body: 'hi' }
    expect(response).to have_http_status(:not_found)
  end

  it 'is closed when the company turned the feature off' do
    grant
    entity.update!(features: { 'b02c' => false })
    sign_in!
    post '/messages', params: { company: entity.id, body: 'hi' }
    expect(response).to have_http_status(:not_found)
  end

  it 'limits the number of messages a person writes in a day' do
    grant
    sign_in!
    Rails.configuration.x.portal_uploads = Rails.configuration.x.portal_uploads # (limits live in Portal::Message)
    stub_const('Portal::Message::PER_DAY', 2)
    3.times { post '/messages', params: { company: entity.id, body: 'hi' } }
    expect(Portal::Message.count).to eq(2)
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'shows the documents sent into the thread, with the messages' do
    grant
    thread = thread_of
    Portal::Upload.create!(entity_id: entity.id, portal_user: person, filename: 'receipt.pdf', byte_size: 1, sha256: 'a' * 64, chunk_size: 1, chunk_count: 1, status: 'received', thread_id: thread.id,
                           received_at: Time.current, expires_at: 1.day.from_now)
    sign_in!
    get '/messages'
    expect(response.body).to include('receipt.pdf')
  end

  it 'ties an upload to the thread' do
    grant
    sign_in!
    post '/uploads', params: { company: entity.id, filename: 'invoice.pdf', byte_size: 1000, sha256: 'a' * 64, thread: 'yes' }, as: :json
    expect(response).to have_http_status(:created)
    expect(Portal::Upload.sole.thread_id).to eq(Portal::MessageThread.find_by(entity_id: entity.id).id)
  end
end
