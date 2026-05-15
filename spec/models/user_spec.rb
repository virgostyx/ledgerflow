require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    subject { build(:user) }

    it { should validate_presence_of(:full_name) }
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
  end

  describe 'enums' do
    it { should define_enum_for(:role)
           .with_values(admin: 0, accountant: 1, manager: 2, auditor: 3, budget_user: 4) }
  end

  describe 'defaults' do
    it 'a le rôle auditor par défaut' do
      user = User.new
      expect(user.role).to eq('auditor')
    end

    it 'est actif par défaut' do
      user = User.new
      expect(user.active).to be true
    end

    it 'a la locale fr par défaut' do
      user = User.new
      expect(user.locale).to eq('fr')
    end
  end

  describe 'rôles' do
    it '#admin? retourne true pour un admin' do
      expect(build(:user, :admin)).to be_admin
    end

    it '#accountant? retourne true pour un comptable' do
      expect(build(:user, :accountant)).to be_accountant
    end

    it '#can_post_entries? retourne true pour admin et accountant' do
      expect(build(:user, :admin).can_post_entries?).to be true
      expect(build(:user, :accountant).can_post_entries?).to be true
      expect(build(:user, :auditor).can_post_entries?).to be false
    end
  end

  describe 'scopes' do
    let!(:active_user)   { create(:user, active: true) }
    let!(:inactive_user) { create(:user, active: false) }

    it '.active retourne uniquement les utilisateurs actifs' do
      expect(User.active).to include(active_user)
      expect(User.active).not_to include(inactive_user)
    end
  end
end
