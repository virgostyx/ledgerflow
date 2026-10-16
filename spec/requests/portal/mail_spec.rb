require 'rails_helper'

# B02b: the dedicated address of the company, with a QR code, for those who may send documents. Only theirs.
RSpec.describe 'Portal: send by e-mail', type: :request do
  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user) }

  def sign_in!
    post '/session', params: { email: person.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(person.totp_secret) }
  end

  before { host! Rails.configuration.x.portal_host }

  it 'shows the address of the company and a QR code that holds nothing else' do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: 'collaborator', capabilities: %w[documents.upload])
    sign_in!

    get '/mail'

    expect(response.body).to include(entity.documents_email, '<svg')
    expect(response.body).to include('Only the people of your company')
  end

  it 'does not show the address of another company, nor to someone who may not send documents' do
    other = create(:entity)
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: 'reader', capabilities: %w[publications.view])
    sign_in!

    get '/mail'

    expect(response.body).not_to include(entity.documents_email)
    expect(response.body).not_to include(other.documents_email)
  end

  it 'asks to be signed in' do
    get '/mail'
    expect(response).to redirect_to('/sign_in')
  end
end
