require 'rails_helper'

RSpec.describe Accounting::ReconcileBankTransaction, type: :service do
  include_context 'with_open_fiscal_year'

  let!(:bank_account_record) { create(:account, code: '550000', label_fr: 'Banque ING',
                                      account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:bank_journal)  { create(:journal, :bank, default_account: bank_account_record) }
  let!(:bank_account)  { create(:bank_account, journal: bank_journal) }
  let!(:counterpart)   { create(:account, code: '400000', label_fr: 'Clients',
                                account_type: :asset, normal_balance: :debit) }

  describe '.call — transaction CRDT (argent entrant)' do
    let!(:transaction) do
      create(:bank_transaction, bank_account: bank_account,
             amount: BigDecimal('1210.00'), description: 'Paiement client')
    end

    subject(:result) do
      described_class.call(
        transaction: transaction,
        account_id:  counterpart.id,
        fiscal_year: fiscal_year,
        label:       'Encaissement client'
      )
    end

    it 'retourne un contexte de succès' do
      expect(result).to be_success
    end

    it 'crée une écriture comptable' do
      expect { result }.to change(Accounting::JournalEntry, :count).by(1)
    end

    it 'valide l écriture (statut posted)' do
      result
      expect(Accounting::JournalEntry.last).to be_posted
    end

    it 'débite le compte bancaire (512)' do
      result
      debit_line = Accounting::JournalEntry.last.lines.find_by(account: bank_account_record)
      expect(debit_line.debit).to eq(BigDecimal('1210.00'))
    end

    it 'crédite le compte contrepartie' do
      result
      credit_line = Accounting::JournalEntry.last.lines.find_by(account: counterpart)
      expect(credit_line.credit).to eq(BigDecimal('1210.00'))
    end

    it 'marque la transaction comme réconciliée' do
      result
      expect(transaction.reload).to be_reconciled
    end

    it 'lie l écriture à la transaction' do
      result
      expect(transaction.reload.journal_entry).to eq(Accounting::JournalEntry.last)
    end
  end

  describe '.call — transaction DBIT (argent sortant)' do
    let!(:supplier) { create(:account, code: '440000', label_fr: 'Fournisseurs',
                             account_type: :liability, normal_balance: :credit) }
    let!(:transaction) do
      create(:bank_transaction, bank_account: bank_account,
             amount: BigDecimal('-500.00'), description: 'Paiement fournisseur')
    end

    subject(:result) do
      described_class.call(
        transaction: transaction,
        account_id:  supplier.id,
        fiscal_year: fiscal_year,
        label:       'Paiement fournisseur'
      )
    end

    it 'débite le compte contrepartie' do
      result
      debit_line = Accounting::JournalEntry.last.lines.find_by(account: supplier)
      expect(debit_line.debit).to eq(BigDecimal('500.00'))
    end

    it 'crédite le compte bancaire (512)' do
      result
      credit_line = Accounting::JournalEntry.last.lines.find_by(account: bank_account_record)
      expect(credit_line.credit).to eq(BigDecimal('500.00'))
    end
  end

  describe '.call — transaction déjà réconciliée' do
    let!(:transaction) do
      create(:bank_transaction, bank_account: bank_account,
             amount: BigDecimal('100.00'), status: :reconciled)
    end

    it 'retourne un échec' do
      result = described_class.call(
        transaction: transaction,
        account_id:  counterpart.id,
        fiscal_year: fiscal_year
      )
      expect(result).to be_failure
    end
  end

  describe '.call — unexpected error' do
    let!(:transaction) do
      create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('100.00'))
    end

    it 'returns a failure context with the error message' do
      allow(ApplicationRecord).to receive(:transaction).and_raise(StandardError, 'unexpected DB error')
      result = described_class.call(
        transaction: transaction,
        account_id:  counterpart.id,
        fiscal_year: fiscal_year
      )
      expect(result).to be_failure
      expect(result.message).to include('unexpected DB error')
    end
  end
end
