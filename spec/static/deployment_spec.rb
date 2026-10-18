require 'rails_helper'
require 'yaml'

# Deployment (stage 1: the firm only, portal closed): what config/deploy.yml and .kamal/secrets must say, and must never say.
RSpec.describe 'Deployment configuration' do
  let(:deploy) { YAML.load_file(Rails.root.join('config/deploy.yml')) }
  let(:secrets_file) { Rails.root.join('.kamal/secrets').read }
  let(:clear) { deploy.dig('env', 'clear') }
  let(:secret) { deploy.dig('env', 'secret') }

  it 'targets the dedicated server, not the one of BudgetFlow' do
    expect(deploy.dig('servers', 'web')).to eq([ '2.24.163.249' ])
    expect(deploy.dig('accessories', 'db', 'host')).to eq('2.24.163.249')
    expect(deploy['ssh']).to include('user' => 'deploy', 'port' => 22)
    expect(Rails.root.join('config/deploy.yml').read).not_to match(/budgetflow/i)
  end

  it 'serves the application on its own host with a certificate' do
    expect(deploy['proxy']).to include('ssl' => true, 'host' => 'app.ledgerflowmanagment.com')
    expect(clear['APP_HOST']).to eq('app.ledgerflowmanagment.com')
  end

  it 'keeps PostgreSQL local to the server' do
    expect(deploy.dig('accessories', 'db', 'port')).to eq('127.0.0.1:5432:5432')
  end

  it 'checks the database that exists, not one named after the user' do
    expect(deploy.dig('accessories', 'db', 'options', 'health-cmd')).to include('-d ledgerflow_production')
  end

  it 'gives the first start time to prepare the four databases' do
    expect(deploy['deploy_timeout']).to be >= 120
  end

  it 'sends the mail through the SMTP of the sender mailbox, the password being a secret' do
    expect(clear).to include('SMTP_ADDRESS' => 'smtp.hostinger.com', 'SMTP_PORT' => 465, 'SMTP_DOMAIN' => 'ledgerflowmanagment.com',
                             'SMTP_USERNAME' => 'no-reply@ledgerflowmanagment.com', 'MAILER_FROM' => 'no-reply@ledgerflowmanagment.com')
    expect(secret).to include('SMTP_PASSWORD')
    expect(clear.keys).not_to include('SMTP_PASSWORD')
  end

  it 'mounts the signing keys from the host, outside the storage volume' do
    host, container = deploy['volumes'].map { |volume| volume.split(':') }.find { |_, target| target == clear['LEDGER_SIGNING_KEY_DIR'] }
    expect(host).to eq('/var/lib/ledgerflow/signing_keys')
    expect(container).to eq('/rails/signing_keys')
    expect(container).not_to start_with('/rails/storage')
  end

  it 'reads every secret from .kamal/secrets, which holds no value' do
    names = secret + deploy.dig('accessories', 'db', 'env', 'secret') + [ deploy.dig('registry', 'password') ].flatten
    names.each { |name| expect(secrets_file).to match(/^#{name}=\$/), "#{name} must be read from the workstation, never written in the file" }
    expect(secrets_file.lines.grep(/^[A-Z_]+=(?!\$)\S/)).to be_empty
  end

  it 'keeps closed what stage 1 leaves closed' do
    forbidden = %w[PORTAL_HOST PORTAL_DATABASE_URL WEBHOOKS_ALLOW_HTTP WEBHOOKS_ALLOW_PRIVATE LEGACY_JWT_ENABLED LEDGERFLOW_JWT_SECRET
                   AGENT_ALLOW_LIVE_PROVIDER ANTHROPIC_API_KEY DOCUMENT_VIRUS_SCAN_FAIL_OPEN]
    expect(clear.keys + secret).not_to include(*forbidden)
  end

  it 'pulls its image from the private repository of the account' do
    expect(deploy['image']).to eq('virgostyx/ledgerflow')
    expect(deploy['registry']['username']).to eq('virgostyx')
  end
end
