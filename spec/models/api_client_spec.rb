require 'rails_helper'

RSpec.describe ApiClient, type: :model do
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  def build_client(**attrs)
    described_class.new({ entity: entity, name: 'BudgetFlow', scopes: %w[invoices:write] }.merge(attrs))
  end

  describe '.issue!' do
    it 'returns the client and a plaintext key that is never stored' do
      client, key = described_class.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[invoices:write])

      expect(key).to start_with('lf_')
      expect(client.key_digest).not_to include(key)
      expect(described_class.authenticate(key)).to eq(client)
    end
  end

  describe '.authenticate' do
    it 'returns nil for an unknown key' do
      expect(described_class.authenticate('lf_nope')).to be_nil
    end

    it 'returns nil once the client is revoked' do
      client, key = described_class.issue!(entity: entity, name: 'BudgetFlow', scopes: [])
      client.revoke!

      expect(described_class.authenticate(key)).to be_nil
    end
  end

  describe '#allows?' do
    it 'checks the scope list' do
      client = build_client(scopes: %w[invoices:read])

      expect(client.allows?('invoices:read')).to be true
      expect(client.allows?('invoices:write')).to be false
    end
  end

  describe 'validations' do
    it 'requires a name' do
      expect(build_client(name: '')).not_to be_valid
    end

    it 'rejects unknown scopes' do
      expect(build_client(scopes: %w[everything])).not_to be_valid
    end
  end

  describe '#rotate!' do
    it 'invalidates the previous key' do
      client, old_key = described_class.issue!(entity: entity, name: 'BudgetFlow', scopes: [])
      new_key = client.rotate!

      expect(described_class.authenticate(old_key)).to be_nil
      expect(described_class.authenticate(new_key)).to eq(client)
    end
  end
end
