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

  describe 'bound to its owner (F01: a key never has more rights than the person behind it)' do
    def owner_with(role, **attrs) = create(:user).tap { |user| create(:user_entity, role, user: user, entity: entity, **attrs) }
    def owned_client(**attrs) = build_client(key_digest: SecureRandom.hex(8), **attrs)

    it 'is valid when every scope is within the owner\'s rights' do
      %i[admin accountant assistant].each do |role|
        expect(owned_client(owner: owner_with(role), scopes: %w[invoices:read invoices:write partners:write])).to be_valid
      end
    end

    it 'refuses, at creation, a scope the owner could not use by hand' do
      client = owned_client(owner: owner_with(:manager), scopes: %w[invoices:read invoices:write])

      expect(client).not_to be_valid
      expect(client.errors[:scopes].join).to match(/invoices:write/)
    end

    it 'lets a read-only owner hold a read key' do
      expect(owned_client(owner: owner_with(:auditor), scopes: %w[invoices:read])).to be_valid
    end

    it 'refuses an owner who has no access to the entity' do
      expect(owned_client(owner: create(:user), scopes: %w[invoices:read])).not_to be_valid
    end

    it 'refuses an owner whose access expired' do
      expect(owned_client(owner: owner_with(:accountant, valid_until: Date.current - 1), scopes: %w[invoices:read])).not_to be_valid
    end

    it 'stops allowing a scope the moment the owner loses the right (checked at every use)' do
      owner = owner_with(:accountant)
      client = owned_client(owner: owner, scopes: %w[invoices:write]).tap(&:save!)
      expect(client.allows?('invoices:write')).to be true

      UserEntity.find_by(user: owner, entity: entity).update!(role: :manager)

      expect(client.reload.allows?('invoices:write')).to be false
    end

    it 'stops allowing anything once the owner\'s access is deactivated or expired' do
      owner = owner_with(:accountant)
      client = owned_client(owner: owner, scopes: %w[invoices:read invoices:write]).tap(&:save!)

      UserEntity.find_by(user: owner, entity: entity).update!(active: false)

      expect(client.reload.allows?('invoices:read')).to be false
      expect(client.allows?('invoices:write')).to be false
    end

    it 'may post invoices only if the owner may validate' do
      expect(owned_client(owner: owner_with(:accountant)).may_post?).to be true
      expect(owned_client(owner: owner_with(:assistant)).may_post?).to be false
    end

    it 'keeps a key without owner working as before (keys issued before F01)' do
      client = owned_client(scopes: %w[invoices:read invoices:write])

      expect(client).to be_valid
      expect(client.allows?('invoices:write')).to be true
      expect(client.may_post?).to be true
    end
  end
end
