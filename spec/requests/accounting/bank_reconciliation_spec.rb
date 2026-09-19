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

  describe 'suggestions' do
    let!(:invoice) do
      create(:invoice, :customer, :posted, fiscal_year: fiscal_year).tap { |i| i.update_columns(total_incl_vat: BigDecimal('1210')) }
    end
    let(:comm) { Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(invoice.id)) }
    let!(:receipt) do
      create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1210'), description: "Payment #{comm}")
    end
    let(:accept) { { bank_reconciliation: { bank_transaction_id: receipt.id, accept_suggestion: '1' } } }

    it 'shows the suggested invoice on the review page' do
      get accounting_bank_reconciliation_path
      expect(response.body).to include('Suggested').and include(invoice.invoice_number.to_s)
    end

    it 'shows the excess of an overpayment in the suggestion' do
      receipt.update_columns(amount: BigDecimal('1500'))
      get accounting_bank_reconciliation_path

      expect(response.body).to include('overpaid by').and include(Accounting::MoneyPresenter.new(BigDecimal('290')).format)
    end

    context 'with a grouped transfer' do
      let!(:second) do
        create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: invoice.partner, invoice_number: 'GRP-0002')
          .tap { |i| i.update_columns(total_incl_vat: BigDecimal('300')) }
      end
      let!(:group_tx) do
        invoice.update_columns(invoice_number: 'GRP-0001')
        create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1510'),
               description: 'Invoices GRP-0001 and GRP-0002')
      end
      let(:accept_group) { { bank_reconciliation: { bank_transaction_id: group_tx.id, accept_suggestion: '1' } } }

      it 'lists the invoices in the suggestion' do
        get accounting_bank_reconciliation_path
        expect(response.body).to include('GRP-0001').and include('GRP-0002')
      end

      it 'books an accepted grouped suggestion and pays every invoice' do
        patch accounting_bank_reconciliation_path, params: accept_group

        expect(group_tx.reload).to be_reconciled
        expect(invoice.reload).to be_paid
        expect(second.reload).to be_paid
      end
    end

    it 'tucks manual reconciliation behind a link when a suggestion exists' do
      get accounting_bank_reconciliation_path
      expect(response.body).to include('Reconcile manually')
    end

    it 'shows the manual form directly when there is no suggestion' do
      receipt.update_columns(description: 'nothing to match')
      get accounting_bank_reconciliation_path

      expect(response.body).to include('value="Reconcile"')
      expect(response.body).not_to include('Reconcile manually')
    end

    it 'books an accepted invoice suggestion and pays the invoice' do
      patch accounting_bank_reconciliation_path, params: accept

      expect(receipt.reload).to be_reconciled
      expect(invoice.reload).to be_paid
      expect(response).to redirect_to(accounting_bank_reconciliation_path)
    end

    it 'links an accepted payment batch suggestion without a new entry' do
      entry = create(:journal_entry, fiscal_year: fiscal_year)
      batch = create(:payment_batch, :executed, bank_account: bank_account, total_amount: BigDecimal('300'), journal_entry: entry)
      debit = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-300'), reference: batch.message_id)

      expect {
        patch accounting_bank_reconciliation_path,
              params: { bank_reconciliation: { bank_transaction_id: debit.id, accept_suggestion: '1' } }
      }.not_to change(Accounting::JournalEntry, :count)

      expect(debit.reload.journal_entry).to eq(batch.journal_entry)
    end

    it 'refuses to accept when there is no suggestion' do
      plain = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('5'), description: 'nothing')

      patch accounting_bank_reconciliation_path,
            params: { bank_reconciliation: { bank_transaction_id: plain.id, accept_suggestion: '1' } }

      expect(plain.reload).to be_pending
      expect(flash[:alert]).to be_present
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
