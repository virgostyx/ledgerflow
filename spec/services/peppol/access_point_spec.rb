require 'rails_helper'

RSpec.describe Peppol::AccessPoint do
  describe '.for' do
    it 'gives the adapter of the provider the entity chose, built for that entity' do
      simulator = described_class.for(build(:entity, peppol_access_point: :simulator))
      digiteal  = described_class.for(build(:entity, peppol_access_point: :digiteal, peppol_credentials: { 'api_key' => 'k', 'webhook_secret' => 's' }))

      expect(simulator).to be_a(Peppol::AccessPoint::Simulator)
      expect(digiteal).to be_a(Peppol::AccessPoint::Digiteal)
      expect(digiteal.entity).to be_a(Entity)
    end

    it 'shares one adapter class between entities of the same provider, each with its own credentials' do
      a = create(:entity, peppol_access_point: :digiteal, peppol_credentials: { 'api_key' => 'key-a', 'webhook_secret' => 's-a' })
      b = create(:entity, peppol_access_point: :digiteal, peppol_credentials: { 'api_key' => 'key-b', 'webhook_secret' => 's-b' })

      expect(described_class.for(a).class).to eq(described_class.for(b).class)
      expect(described_class.for(a).entity).not_to eq(described_class.for(b).entity)
    end

    it 'raises NotConfigured for an entity without an Access Point' do
      expect { described_class.for(build(:entity)) }.to raise_error(Peppol::AccessPoint::NotConfigured)
    end
  end

  describe '.credential_fields' do
    it 'lets the settings screen ask for what a provider needs, without an instance' do
      expect(described_class.credential_fields(:digiteal).map { |f| f[:key] }).to include('api_key', 'webhook_secret')
      expect(described_class.credential_fields(:simulator)).to eq([])
    end
  end

  describe 'the error classes' do
    it 'are all Peppol::AccessPoint::Error, so one rescue covers them' do
      expect(Peppol::AccessPoint::NotConfigured.ancestors).to include(Peppol::AccessPoint::Error)
      expect(Peppol::AccessPoint::InvalidSignature.ancestors).to include(Peppol::AccessPoint::Error)
    end
  end
end
