require 'rails_helper'

RSpec.describe UserEntity, type: :model do
  subject { build(:user_entity) }

  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:entity) }
  end

  describe 'validations' do
    it { should validate_presence_of(:role) }

    it 'rejette la duplication (user_id, entity_id)' do
      user   = create(:user)
      entity = create(:entity)
      create(:user_entity, user: user, entity: entity)
      duplicate = build(:user_entity, user: user, entity: entity)
      expect(duplicate).not_to be_valid
    end
  end

  describe 'enums' do
    it { should define_enum_for(:role)
           .with_values(admin: 0, accountant: 1, manager: 2, auditor: 3) }
  end

  describe 'scopes' do
    let(:entity) { create(:entity) }
    let!(:active_ue)   { create(:user_entity, entity: entity, active: true) }
    let!(:inactive_ue) { create(:user_entity, entity: entity, active: false) }

    it '.active retourne les memberships actifs' do
      expect(UserEntity.active).to include(active_ue)
      expect(UserEntity.active).not_to include(inactive_ue)
    end
  end

  describe 'role helpers' do
    it '#admin? retourne true pour un admin' do
      expect(build(:user_entity, :admin)).to be_admin
    end

    it '#accountant? retourne true pour un accountant' do
      expect(build(:user_entity, :accountant)).to be_accountant
    end
  end
end
