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
           .with_values(admin: 0, accountant: 1, manager: 2, auditor: 3, assistant: 4) }
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

  describe '.current (F01: access valid today)' do
    let(:entity) { create(:entity) }

    def membership(**attrs) = create(:user_entity, :accountant, entity: entity, **attrs)

    it 'includes an open-ended membership' do
      expect(UserEntity.current).to include(membership)
    end

    it 'includes the first and the last day of the validity window' do
      first = membership(valid_from: Date.current)
      last  = membership(valid_until: Date.current)

      expect(UserEntity.current).to include(first, last)
    end

    it 'excludes an access not started yet, an expired one and a deactivated one' do
      future   = membership(valid_from: Date.current + 1)
      expired  = membership(valid_until: Date.current - 1)
      inactive = membership(active: false)

      expect(UserEntity.current).not_to include(future, expired, inactive)
    end

    it 'refuses a window that ends before it starts' do
      expect(build(:user_entity, valid_from: Date.current, valid_until: Date.current - 1)).not_to be_valid
    end
  end

  describe 'the last owner (F01)' do
    let(:entity) { create(:entity) }
    let!(:owner) { create(:user_entity, :admin, entity: entity) }

    it 'cannot be demoted' do
      expect(owner.update(role: :accountant)).to be false
      expect(owner.errors[:base]).to include(a_string_matching(/last owner/i))
    end

    it 'cannot be deactivated' do
      expect(owner.update(active: false)).to be false
    end

    it 'cannot be given an expiry date' do
      expect(owner.update(valid_until: Date.current + 30)).to be false
    end

    it 'cannot be removed' do
      expect(owner.destroy).to be false
      expect(UserEntity.exists?(owner.id)).to be true
    end

    it 'can be demoted, deactivated or removed once another owner exists' do
      create(:user_entity, :admin, entity: entity)

      expect(owner.update(role: :accountant)).to be true
    end

    it 'does not stop the entity from being deleted with its memberships' do
      expect { entity.destroy! }.to change(UserEntity, :count).by(-1)
    end

    it 'is not removed by deleting the user account either' do
      expect(owner.user.destroy).to be false
      expect(UserEntity.exists?(owner.id)).to be true
    end

    it 'does not count an owner of another entity' do
      create(:user_entity, :admin)

      expect(owner.update(role: :accountant)).to be false
    end
  end
end
