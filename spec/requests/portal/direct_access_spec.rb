require 'rails_helper'

# B02a, criterion 3: the suite is drawn from the routes file. Every route of the portal that carries an identifier is answered 404 when the object is outside the
# scope of the person; every route that is not on the public list sends an unsigned visitor to the sign-in. A route added without its line here fails the suite.
RSpec.describe 'Portal direct access to identifiers', type: :request do
  # Routes anyone may reach (they hold no data): controller#action
  def public_routes = %w[portal/sessions#new portal/sessions#create portal/invitations#show portal/invitations#accept portal/second_factors#new portal/second_factors#create
                         portal/second_factors#challenge portal/second_factors#verify portal/sessions#destroy portal/branding#stylesheet]

  # Routes with an identifier: how to build a path to an object this person must not see, given the person and a stranger's data.
  def probes
    {
      'portal/invitations#show'   => ->(_ctx) { '/invitations/not-a-token' },
      'portal/invitations#accept' => ->(_ctx) { '/invitations/not-a-token' },
      # a publication of a company where this person has no right, and a file link signed for someone else
      'portal/publications#show'  => ->(ctx) { "/publications/#{ctx[:foreign_publication].token}" },
      'portal/devices#destroy'    => ->(ctx) { "/devices/#{ctx[:foreign_device].token}" },
      'portal/downloads#show'     => ->(ctx) { "/downloads/#{Portal::DownloadLink.for(ctx[:stranger], ctx[:foreign_publication].files.first)}" }
    }
  end

  def portal_routes
    Rails.application.routes.routes.select { |r| r.verb.present? && r.defaults[:controller].to_s.start_with?('portal/') }
  end

  before { host! Rails.configuration.x.portal_host }

  it 'finds the routes of the portal' do
    expect(portal_routes.map { |r| "#{r.defaults[:controller]}##{r.defaults[:action]}" }).to include('portal/home#show', 'portal/invitations#show')
  end

  it 'sends an unsigned visitor to the sign-in on every page that is not public' do
    private_routes = portal_routes.reject { |r| public_routes.include?("#{r.defaults[:controller]}##{r.defaults[:action]}") }
    expect(private_routes).not_to be_empty

    private_routes.each do |route|
      verb = route.verb.downcase
      path = route.path.spec.to_s.sub('(.:format)', '').gsub(/:\w+/, 'x')
      send(verb, path)
      expect(response).to redirect_to('/sign_in'), "#{verb.upcase} #{path} should send an unsigned visitor to the sign-in, got #{response.status}"
    end
  end

  it 'has a probe for every route that carries an identifier' do
    carrying = portal_routes.select { |r| r.path.required_names.any? }.map { |r| "#{r.defaults[:controller]}##{r.defaults[:action]}" }
    expect(carrying - probes.keys).to be_empty, "add a probe for: #{(carrying - probes.keys).join(', ')}"
  end

  it 'answers 404 to an object outside the scope, whoever asks' do
    user = create(:portal_user)
    post '/session', params: { email: user.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }

    foreign_publication = PortalAdmin::Publish.call(entity: create(:entity), kind: 'other', title: 'Not yours', by: create(:user),
                                                    files: [ { filename: 'a.pdf', content_type: 'application/pdf', data: '%PDF-1.4' } ])[:publication]
    foreign_device = Portal::Device.create!(portal_user: create(:portal_user), token: 'foreigndevice', token_digest: 'zz', first_seen_at: Time.current, last_seen_at: Time.current)
    context = { foreign_device: foreign_device, user: user, foreign_publication: foreign_publication, stranger: create(:portal_user) }

    probes.each do |key, build|
      route = portal_routes.find { |r| "#{r.defaults[:controller]}##{r.defaults[:action]}" == key }
      send(route.verb.downcase, build.call(context))
      expect(response).to have_http_status(:not_found), "#{key} answered #{response.status} to an object outside the scope"
    end
  end
end
