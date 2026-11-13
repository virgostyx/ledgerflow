require 'rails_helper'
require 'active_storage/service/s3_service'

# Production stores the documents in a private Cloudflare R2 bucket (S3 API). The service is read from config/storage.yml
# with the LEDGERFLOW_R2_* variables; no network call is made here, the client is only built.
RSpec.describe 'Active Storage service "cloudflare"' do
  let(:env) do
    {
      'LEDGERFLOW_R2_ACCESS_KEY_ID' => 'key-id', 'LEDGERFLOW_R2_SECRET_ACCESS_KEY' => 'secret',
      'LEDGERFLOW_R2_BUCKET' => 'documents-bucket', 'LEDGERFLOW_R2_ENDPOINT' => 'https://abc123.r2.cloudflarestorage.com'
    }
  end
  let(:service) do
    allow(ENV).to receive(:[]).and_call_original
    env.each { |k, v| allow(ENV).to receive(:[]).with(k).and_return(v) }
    configs = ActiveSupport::ConfigurationFile.parse(Rails.root.join('config/storage.yml')).deep_symbolize_keys
    ActiveStorage::Service.configure(:cloudflare, configs)
  end

  it 'is an S3 service on the configured bucket' do
    expect(service).to be_a(ActiveStorage::Service::S3Service)
    expect(service.bucket.name).to eq('documents-bucket')
  end

  it 'talks to the R2 endpoint, region "auto"' do
    client = service.bucket.client
    expect(client.config.endpoint.to_s).to eq('https://abc123.r2.cloudflarestorage.com')
    expect(client.config.region).to eq('auto')
  end

  it 'only computes checksums when required (R2 refuses the SDK default)' do
    config = service.bucket.client.config
    expect(config.request_checksum_calculation).to eq('when_required')
    expect(config.response_checksum_validation).to eq('when_required')
  end

  it 'keeps the test and development environments on disk' do
    expect(Rails.configuration.active_storage.service).to eq(:test)
  end
end
