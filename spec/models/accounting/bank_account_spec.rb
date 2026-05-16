require 'rails_helper'

RSpec.describe Accounting::BankAccount, type: :model do
  describe 'associations' do
    it { should belong_to(:journal).class_name('Accounting::Journal') }
    it { should have_many(:transactions).class_name('Accounting::BankTransaction').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:bank_account) }

    it { should validate_presence_of(:label_fr) }
    it { should validate_presence_of(:iban) }

    it 'rejette un IBAN invalide' do
      expect(build(:bank_account, iban: 'BE00000000000000')).not_to be_valid
    end

    it 'accepte un IBAN belge valide' do
      expect(build(:bank_account, iban: 'BE71096123456769')).to be_valid
    end
  end

  describe 'defaults' do
    it 'est actif par défaut' do
      expect(build(:bank_account).active).to be true
    end

    it 'a une devise EUR par défaut' do
      expect(build(:bank_account).currency).to eq('EUR')
    end
  end
end
