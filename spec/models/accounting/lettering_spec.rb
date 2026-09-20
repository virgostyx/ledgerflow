require 'rails_helper'

RSpec.describe Accounting::Lettering, type: :model do
  include_context 'with entity'

  describe 'associations' do
    it { should belong_to(:account).class_name('Accounting::Account') }
    it { should belong_to(:partner).class_name('Accounting::Partner').optional }
    it { should have_many(:lines).class_name('Accounting::JournalEntryLine').with_foreign_key(:lettering_id).dependent(:nullify) }
  end

  describe 'validations' do
    it { should validate_presence_of(:code) }
    it { should validate_presence_of(:lettered_on) }

    it 'requires a code unique per account' do
      existing = create(:lettering, code: 'AA')
      dup = build(:lettering, account: existing.account, code: 'AA')
      expect(dup).not_to be_valid
    end

    it 'allows the same code on another account' do
      create(:lettering, code: 'AA')
      expect(build(:lettering, code: 'AA')).to be_valid
    end
  end

  describe '.next_code_for' do
    let(:account) { create(:account) }

    it 'starts at AA' do
      expect(described_class.next_code_for(account)).to eq('AA')
    end

    it 'increments the last code of the account' do
      create(:lettering, account: account, code: 'AA')
      expect(described_class.next_code_for(account)).to eq('AB')
    end

    it 'rolls over after AZ' do
      create(:lettering, account: account, code: 'AZ')
      expect(described_class.next_code_for(account)).to eq('BA')
    end
  end
end
