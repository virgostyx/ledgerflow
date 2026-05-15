require 'rails_helper'

RSpec.describe Accounting::JournalEntryLine, type: :model do
  describe 'associations' do
    it { should belong_to(:journal_entry).class_name('Accounting::JournalEntry') }
    it { should belong_to(:account).class_name('Accounting::Account') }
  end

  describe 'validations de la partie double' do
    it 'est invalide si débit ET crédit sont positifs simultanément' do
      line = build(:journal_entry_line, debit: '100.00', credit: '50.00')
      expect(line).not_to be_valid
      expect(line.errors[:base]).to include(I18n.t('accounting.errors.dual_side'))
    end

    it 'est invalide si débit ET crédit sont nuls' do
      line = build(:journal_entry_line, debit: '0', credit: '0')
      expect(line).not_to be_valid
      expect(line.errors[:base]).to include(I18n.t('accounting.errors.zero_side'))
    end

    it 'est valide avec un débit positif et crédit nul' do
      line = build(:journal_entry_line, debit: '100.00', credit: '0')
      expect(line).to be_valid
    end

    it 'est valide avec un crédit positif et débit nul' do
      line = build(:journal_entry_line, debit: '0', credit: '100.00')
      expect(line).to be_valid
    end
  end

  describe 'précision monétaire (MonetaryPrecision)' do
    it 'convertit automatiquement un Float en BigDecimal' do
      line = build(:journal_entry_line, debit: 100.0, credit: 0.0)
      expect(line.debit).to be_a(BigDecimal)
    end
  end

  describe 'trigger DB — partie double' do
    it 'rejette une ligne déséquilibrée au niveau DB' do
      entry = create(:journal_entry)
      expect {
        create(:journal_entry_line, journal_entry: entry,
               debit: BigDecimal('100.00'), credit: BigDecimal('0'))
      }.to raise_error(ActiveRecord::StatementInvalid, /Unbalanced entry/)
    end
  end
end
