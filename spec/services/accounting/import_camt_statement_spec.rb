require 'rails_helper'

RSpec.describe Accounting::ImportCamtStatement, type: :service do
  include_context 'with entity'

  let!(:bank_journal)  { create(:journal, :bank) }
  let!(:bank_account)  { create(:bank_account, journal: bank_journal, iban: 'BE71096123456769') }

  let(:camt_xml) { File.read(Rails.root.join('spec/fixtures/files/sample_camt.xml')) }

  describe '.call' do
    subject(:result) { described_class.call(xml: camt_xml, bank_account: bank_account) }

    it 'retourne un contexte de succès' do
      expect(result).to be_success
    end

    it 'crée les transactions bancaires' do
      expect { result }.to change(Accounting::BankTransaction, :count).by(2)
    end

    it 'importe correctement la transaction CRDT' do
      result
      tx = Accounting::BankTransaction.find_by(reference: 'E2E-001')
      expect(tx).to be_present
      expect(tx.amount).to eq(BigDecimal('1210.00'))
      expect(tx.transaction_date).to eq(Date.new(2025, 1, 15))
      expect(tx.description).to eq('Paiement client ABC')
    end

    it 'importe correctement la transaction DBIT (montant négatif)' do
      result
      tx = Accounting::BankTransaction.find_by(reference: 'E2E-002')
      expect(tx).to be_present
      expect(tx.amount).to eq(BigDecimal('-500.00'))
    end

    it 'démarre les transactions en statut pending' do
      result
      expect(Accounting::BankTransaction.all).to all(be_pending)
    end

    it 'expose le nombre de transactions importées dans le contexte' do
      expect(result[:imported_count]).to eq(2)
    end

    context 'avec des doublons (même référence)' do
      before { described_class.call(xml: camt_xml, bank_account: bank_account) }

      it 'ne réimporte pas les transactions existantes' do
        expect { result }.not_to change(Accounting::BankTransaction, :count)
      end

      it 'retourne un contexte de succès avec count 0' do
        expect(result[:imported_count]).to eq(0)
      end
    end
  end
end
