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

    it 'a la locale en par défaut' do
      user = User.new
      expect(user.locale).to eq('en')
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

  describe 'second factor (F01)' do
    let(:user) { create(:user) }

    def membership(role, entity: create(:entity, features: { 'f01' => true }), **attrs) = create(:user_entity, role, user: user, entity: entity, **attrs)

    describe '#second_factor_required?' do
      it 'is required of someone who can validate, unlock or administer, where F01 is on' do
        membership(:accountant)

        expect(user.second_factor_required?).to be true
      end

      it 'is required of an owner' do
        membership(:admin)

        expect(user.second_factor_required?).to be true
      end

      it 'is not required of an assistant, a reader or an external auditor' do
        %i[assistant manager auditor].each { |role| membership(role) }

        expect(user.second_factor_required?).to be false
      end

      it 'is not required while F01 is off for the entity' do
        membership(:admin, entity: create(:entity, features: { 'f01' => false }))

        expect(user.second_factor_required?).to be false
      end

      it 'ignores an access that expired or was deactivated' do
        membership(:accountant, valid_until: Date.current - 1)
        membership(:admin, active: false)

        expect(user.second_factor_required?).to be false
      end

      it 'is required as soon as one of several entities asks for it' do
        membership(:auditor)
        membership(:accountant)

        expect(user.second_factor_required?).to be true
      end
    end

    describe 'enrolling' do
      it 'stays off until a code from the authenticator confirms the secret' do
        secret = user.begin_totp_enrollment!

        expect(secret).to match(/\A[A-Z2-7]{32}\z/)
        expect(user.reload.totp_enabled?).to be false
        expect(user.confirm_totp!('000000')).to be false
        expect(user.reload.totp_enabled?).to be false

        expect(user.confirm_totp!(Totp.code(secret))).to be true
        expect(user.reload.totp_enabled?).to be true
      end

      it 'keeps the same pending secret if the user comes back to the page' do
        expect(user.begin_totp_enrollment!).to eq(user.begin_totp_enrollment!)
      end

      it 'stores the secret encrypted' do
        secret = user.begin_totp_enrollment!

        raw = User.connection.select_value("SELECT totp_secret FROM users WHERE id = #{user.id}")
        expect(raw).not_to include(secret)
      end

      it 'does not let the code that confirmed the enrolment be used again to sign in' do
        secret = user.begin_totp_enrollment!
        code = Totp.code(secret)
        user.confirm_totp!(code)

        expect(user.reload.verify_totp!(code)).to be false
      end
    end

    describe '#verify_totp!' do
      let!(:secret) { user.begin_totp_enrollment!.tap { |s| user.confirm_totp!(Totp.code(s, Time.current - 30)) } }

      it 'accepts a current code once, then refuses it as a replay' do
        code = Totp.code(secret)

        expect(user.reload.verify_totp!(code)).to be true
        expect(user.reload.verify_totp!(code)).to be false
      end

      it 'refuses a wrong code' do
        expect(user.reload.verify_totp!('123456')).to be false
      end

      it 'refuses everything when no second factor is enrolled' do
        expect(create(:user).verify_totp!('123456')).to be false
      end

      it 'accepts only one of two concurrent uses of the same code' do
        code = Totp.code(secret)
        a = User.find(user.id)
        b = User.find(user.id)

        expect([ a.verify_totp!(code), b.verify_totp!(code) ]).to contain_exactly(true, false)
      end
    end

    describe '#disable_totp!' do
      it 'forgets the secret' do
        secret = user.begin_totp_enrollment!
        user.confirm_totp!(Totp.code(secret))

        user.disable_totp!

        expect(user.reload).not_to be_totp_enabled
        expect(user.totp_secret).to be_nil
      end
    end
  end
end
