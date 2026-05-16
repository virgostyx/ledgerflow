require 'rails_helper'

RSpec.describe Accounting::BankTransaction, type: :model do
  let!(:bank_journal) { create(:journal, :bank) }
  let!(:bank_account) { create(:bank_account, journal: bank_journal) }

  describe 'associations' do
    it { should belong_to(:bank_account).class_name('Accounting::BankAccount') }
    it { should belong_to(:journal_entry).class_name('Accounting::JournalEntry').optional }
  end

  describe 'validations' do
    subject { build(:bank_transaction, bank_account: bank_account) }

    it { should validate_presence_of(:transaction_date) }
    it { should validate_presence_of(:amount) }
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(pending: 0, reconciled: 1, ignored: 2) }
  end

  describe 'scopes' do
    let!(:pending_tx)    { create(:bank_transaction, bank_account: bank_account, status: :pending) }
    let!(:reconciled_tx) { create(:bank_transaction, bank_account: bank_account, status: :reconciled) }

    it '.pending retourne seulement les transactions en attente' do
      expect(Accounting::BankTransaction.pending).to include(pending_tx)
      expect(Accounting::BankTransaction.pending).not_to include(reconciled_tx)
    end
  end

  describe 'defaults' do
    it 'démarre en statut pending' do
      tx = build(:bank_transaction, bank_account: bank_account)
      expect(tx.status).to eq('pending')
    end

    it '#credit? retourne true si amount positif' do
      tx = build(:bank_transaction, bank_account: bank_account, amount: BigDecimal('100'))
      expect(tx.credit?).to be true
    end

    it '#debit? retourne true si amount négatif' do
      tx = build(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-100'))
      expect(tx.debit?).to be true
    end
  end
end
