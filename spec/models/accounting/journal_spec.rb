require 'rails_helper'

RSpec.describe Accounting::Journal, type: :model do
  describe 'validations' do
    subject { build(:journal) }

    it { should validate_presence_of(:code) }
    it { should validate_presence_of(:label_fr) }
    it { should validate_presence_of(:journal_type) }
    it { should validate_presence_of(:sequence_prefix) }
    it { should validate_uniqueness_of(:code) }
  end

  describe 'enums' do
    it { should define_enum_for(:journal_type)
           .with_values(purchase: 0, sale: 1, bank: 2, cash: 3, misc: 4, payroll: 5) }
  end

  describe '#next_sequence_number' do
    it 'incrémente la séquence et retourne la référence formatée' do
      journal = create(:journal, :purchase, current_sequence: 0)
      ref = journal.next_sequence_number(year: 2025)
      expect(ref).to eq('ACH2025/0001')
      expect(journal.reload.current_sequence).to eq(1)
    end

    it 'génère des références uniques en séquence' do
      journal = create(:journal, :sale, current_sequence: 5)
      ref = journal.next_sequence_number(year: 2025)
      expect(ref).to eq('VTE2025/0006')
    end
  end

  describe 'scopes' do
    it '.active retourne les journaux actifs' do
      active   = create(:journal, active: true)
      inactive = create(:journal, :purchase, active: false)
      expect(Accounting::Journal.active).to include(active)
      expect(Accounting::Journal.active).not_to include(inactive)
    end
  end
end
