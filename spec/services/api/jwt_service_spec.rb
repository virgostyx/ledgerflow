require 'rails_helper'

RSpec.describe Api::JwtService do
  describe '.encode / .decode round-trip' do
    let(:payload) { { client: 'budgetflow', project_id: 42 } }

    it 'encode puis decode retourne le payload original' do
      token = described_class.encode(payload)
      decoded = described_class.decode(token)
      expect(decoded['client']).to eq('budgetflow')
      expect(decoded['project_id']).to eq(42)
    end

    it 'ajoute exp et iss au payload' do
      token = described_class.encode(payload)
      decoded = described_class.decode(token)
      expect(decoded['exp']).to be_present
      expect(decoded['iss']).to eq('ledgerflow')
    end
  end

  describe '.decode' do
    it 'lève AuthenticationError pour un token invalide' do
      expect {
        described_class.decode('invalid.token.here')
      }.to raise_error(Api::AuthenticationError)
    end

    it 'lève AuthenticationError pour un token expiré' do
      expired_token = described_class.encode({ client: 'test' })
      travel_to 2.hours.from_now do
        expect {
          described_class.decode(expired_token)
        }.to raise_error(Api::AuthenticationError)
      end
    end
  end
end
