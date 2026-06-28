require 'rails_helper'

RSpec.describe 'Accounting::BankReconciliation', type: :request do
  include_context 'with_open_fiscal_year'

  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)    { create(:user, role: :manager) }

  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager,    user: manager,    entity: entity) }

  let!(:bank_account_record) { create(:account, code: '550000', label_fr: 'Banque ING',
                                      account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:bank_journal)  { create(:journal, :bank, default_account: bank_account_record) }
  let!(:bank_account)  { create(:bank_account, journal: bank_journal) }
  let!(:counterpart)   { create(:account, code: '400000', label_fr: 'Clients',
                                account_type: :asset, normal_balance: :debit) }

  before { sign_in accountant }

  describe 'GET /accounting/bank_reconciliation' do
    it 'retourne 200' do
      get accounting_bank_reconciliation_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /accounting/bank_reconciliation — lettrage' do
    let!(:transaction) do
      create(:bank_transaction, bank_account: bank_account,
             amount: BigDecimal('1210.00'))
    end

    let(:reconcile_params) do
      {
        bank_reconciliation: {
          bank_transaction_id: transaction.id,
          account_id:          counterpart.id,
          label:               'Encaissement client'
        }
      }
    end

    it 'réconcilie la transaction et redirige' do
      patch accounting_bank_reconciliation_path, params: reconcile_params
      expect(response).to redirect_to(accounting_bank_reconciliation_path)
    end

    it 'marque la transaction comme réconciliée' do
      patch accounting_bank_reconciliation_path, params: reconcile_params
      expect(transaction.reload).to be_reconciled
    end
  end

  describe 'PATCH /accounting/bank_reconciliation — import CAMT' do
    let(:camt_file) do
      Rack::Test::UploadedFile.new(
        Rails.root.join('spec/fixtures/files/sample_camt.xml'),
        'application/xml'
      )
    end

    it 'importe les transactions et redirige' do
      expect {
        patch accounting_bank_reconciliation_path, params: {
          bank_reconciliation: {
            bank_account_id: bank_account.id,
            camt_file:       camt_file
          }
        }
      }.to change(Accounting::BankTransaction, :count).by(2)
      expect(response).to redirect_to(accounting_bank_reconciliation_path)
    end
  end

  describe 'PATCH /accounting/bank_reconciliation — lettrage échoué' do
    let!(:reconciled_tx) do
      create(:bank_transaction, bank_account: bank_account,
             amount: BigDecimal('500.00'), status: :reconciled)
    end

    it 'redirige avec alerte si transaction déjà réconciliée' do
      patch accounting_bank_reconciliation_path, params: {
        bank_reconciliation: {
          bank_transaction_id: reconciled_tx.id,
          account_id:          counterpart.id
        }
      }
      expect(response).to redirect_to(accounting_bank_reconciliation_path)
    end
  end

  describe 'accès manager' do
    before { sign_in manager }

    it 'GET retourne 403 ou redirige' do
      get accounting_bank_reconciliation_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
