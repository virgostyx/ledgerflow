require 'rails_helper'
require 'json'
require 'open3'

# config/environments/production.rb is loaded in a child process, with the variables of deploy.yml, so that the test environment cannot hide a mistake.
RSpec.describe 'Production configuration' do
  SENTINEL = 'sentinel-not-a-real-password'.freeze

  def production_env(overrides = {})
    {
      'RAILS_ENV' => 'production', 'SECRET_KEY_BASE_DUMMY' => '1', 'DB_HOST' => 'localhost', 'LEDGERFLOW_DATABASE_PASSWORD' => 'x',
      'APP_HOST' => 'app.example.test', 'MAILER_FROM' => 'no-reply@example.test', 'SMTP_ADDRESS' => 'smtp.example.test', 'SMTP_PORT' => '465',
      'SMTP_DOMAIN' => 'example.test', 'SMTP_USERNAME' => 'no-reply@example.test', 'SMTP_PASSWORD' => SENTINEL
    }.merge(overrides)
  end

  # Runs the Ruby expression in the production environment and returns its JSON.
  def in_production(expression, overrides = {})
    out, err, status = Open3.capture3(production_env(overrides), Rails.root.join('bin/rails').to_s, 'runner', "puts JSON.generate(#{expression})", chdir: Rails.root.to_s)
    [ out.lines.last.to_s, err, status ]
  end

  let(:settings) do
    out, err, status = in_production('[Rails.configuration.action_mailer.delivery_method, Rails.configuration.action_mailer.smtp_settings, ' \
                                     'Rails.configuration.action_mailer.default_url_options, ApplicationMailer.default[:from], Accounting::InvoiceMailer::FROM_ADDRESS]')
    raise "production did not load: #{err}" unless status.success?

    JSON.parse(out)
  end

  it 'sends through the SMTP of the mailbox, in implicit TLS' do
    delivery_method, smtp = settings
    expect(delivery_method).to eq('smtp')
    expect(smtp).to include('address' => 'smtp.example.test', 'port' => 465, 'domain' => 'example.test', 'user_name' => 'no-reply@example.test',
                            'password' => SENTINEL, 'authentication' => 'plain', 'ssl' => true, 'enable_starttls_auto' => false)
  end

  it 'builds the links of the e-mails on the real host, in https' do
    expect(settings[2]).to eq('host' => 'app.example.test', 'protocol' => 'https')
  end

  it 'uses the sender address everywhere, never a placeholder' do
    expect(settings[3]).to eq('no-reply@example.test')
    expect(settings[4]).to eq('no-reply@example.test')
  end

  it 'refuses to start without the mail variables, rather than failing at the first mail' do
    %w[APP_HOST SMTP_ADDRESS SMTP_USERNAME SMTP_PASSWORD SMTP_DOMAIN MAILER_FROM].each do |name|
      _out, err, status = in_production('1', name => nil)
      expect(status).not_to be_success, "#{name} missing must stop the boot"
      expect(err).to include(name)
    end
  end

  it 'answers only to its own host, except for the health check of the proxy' do
    out, err, status = in_production('[Rails.configuration.hosts.map(&:to_s), ' \
                                     '[\'/up\', \'/\'].map { |path| Rails.configuration.host_authorization[:exclude].call(Rack::Request.new(Rack::MockRequest.env_for(path))) }]')
    raise "production did not load: #{err}" unless status.success?

    hosts, excluded = JSON.parse(out)
    expect(hosts).to eq([ 'app.example.test' ])
    expect(excluded).to eq([ true, false ])
  end

  it 'is closed to sign-ups unless OPEN_SIGNUP=1' do
    expect(JSON.parse(in_production('Rails.configuration.x.open_signup')[0])).to be(false)
    expect(JSON.parse(in_production('Rails.configuration.x.open_signup', 'OPEN_SIGNUP' => '1')[0])).to be(true)
  end
end
