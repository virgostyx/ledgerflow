require 'rails_helper'

RSpec.describe Accounting::JournalEntryLine, type: :model do
  include_context 'with entity'

  describe 'associations' do
    it { should belong_to(:journal_entry).class_name('Accounting::JournalEntry') }
    it { should belong_to(:account).class_name('Accounting::Account') }
  end

  describe 'partner' do
    it 'is valid without a partner' do
      expect(build(:journal_entry_line, :debit, partner: nil)).to be_valid
    end

    it 'is valid with a partner of the same entity' do
      expect(build(:journal_entry_line, :debit, partner: create(:partner))).to be_valid
    end

    it 'is invalid with a partner of another entity' do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:partner) }
      line = build(:journal_entry_line, :debit, partner_id: foreign.id)
      expect(line).not_to be_valid
      expect(line.errors[:partner]).to be_present
    end
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

  describe 'entry_date (dénormalisé depuis journal_entry, docs/dev/reports/spec.md §3)' do
    let!(:fiscal_year) { create(:fiscal_year, status: :open, entity: entity) }

    before { ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED') }

    it "reprend la date de l'écriture à la création" do
      entry = create(:journal_entry, fiscal_year: fiscal_year, entry_date: Date.new(2026, 3, 15))
      line  = build(:journal_entry_line, :debit, journal_entry: entry)

      line.save!(validate: false)

      expect(line.entry_date).to eq(Date.new(2026, 3, 15))
    end

    it "se resynchronise si la ligne est ré-attachée à une autre écriture" do
      entry = create(:journal_entry, fiscal_year: fiscal_year, entry_date: Date.new(2026, 3, 15))
      line  = build(:journal_entry_line, :debit, journal_entry: entry)
      line.save!(validate: false)
      other_entry = create(:journal_entry, fiscal_year: fiscal_year, entry_date: Date.new(2026, 4, 1))

      line.journal_entry = other_entry
      line.save!(validate: false)

      expect(line.entry_date).to eq(Date.new(2026, 4, 1))
    end
  end
end
