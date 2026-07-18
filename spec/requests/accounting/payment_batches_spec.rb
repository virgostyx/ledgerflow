require 'rails_helper'

RSpec.describe 'Accounting::PaymentBatches', type: :request do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let(:accountant) { create(:user, role: :accountant) }
  let(:budget_user) { create(:user, role: :budget_user) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:budget_user_membership) { create(:user_entity, :manager, user: budget_user, entity: entity) }

  let(:bank_account) { create(:bank_account) }
  let(:supplier)      { create(:partner, :supplier, :with_iban) }
  let(:invoice) do
    create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year)
  end

  before { sign_in accountant }

  describe 'GET /accounting/payment_batches' do
    it 'returns 200' do
      get accounting_payment_batches_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounting/payment_batches/new' do
    it 'returns 200 and lists eligible invoices' do
      invoice
      get new_accounting_payment_batch_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(invoice.invoice_number)
    end
  end

  describe 'POST /accounting/payment_batches' do
    context 'with a valid selection' do
      it 'creates a draft payment batch and redirects to it' do
        expect {
          post accounting_payment_batches_path, params: {
            accounting_payment_batch: {
              bank_account_id: bank_account.id,
              requested_execution_date: Date.current + 1,
              invoice_ids: [ invoice.id ]
            }
          }
        }.to change(Accounting::PaymentBatch, :count).by(1)

        expect(response).to redirect_to(accounting_payment_batch_path(Accounting::PaymentBatch.last))
        expect(Accounting::PaymentBatch.last).to be_draft
      end
    end

    context 'with no invoices selected' do
      it 'renders new with 422' do
        post accounting_payment_batches_path, params: {
          accounting_payment_batch: {
            bank_account_id: bank_account.id,
            requested_execution_date: Date.current + 1,
            invoice_ids: [ '' ]
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'GET /accounting/payment_batches/:id' do
    let(:payment_batch) { create(:payment_batch, bank_account: bank_account) }

    it 'returns 200' do
      get accounting_payment_batch_path(payment_batch)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /accounting/payment_batches/:id/generate' do
    let(:payment_batch) { create(:payment_batch, bank_account: bank_account, status: :draft) }
    let!(:payment_batch_line) do
      create(:payment_batch_line, payment_batch: payment_batch, invoice: invoice, amount: invoice.total_incl_vat)
    end

    it 'generates the SEPA file and redirects' do
      post generate_accounting_payment_batch_path(payment_batch)
      expect(payment_batch.reload).to be_generated
      expect(response).to redirect_to(accounting_payment_batch_path(payment_batch))
    end

    it 'redirects with an alert when the batch is not draft' do
      payment_batch.update!(status: :cancelled)
      post generate_accounting_payment_batch_path(payment_batch)
      expect(response).to redirect_to(accounting_payment_batch_path(payment_batch))
      expect(flash[:alert]).to be_present
    end
  end

  describe 'POST /accounting/payment_batches/:id/execute' do
    let(:payment_batch) { create(:payment_batch, bank_account: bank_account, status: :generated) }
    let!(:payment_batch_line) do
      create(:payment_batch_line, payment_batch: payment_batch, invoice: invoice, amount: invoice.total_incl_vat)
    end

    it 'executes the batch, settles the invoices and redirects' do
      post execute_accounting_payment_batch_path(payment_batch)
      expect(payment_batch.reload).to be_executed
      expect(invoice.reload).to be_paid
      expect(response).to redirect_to(accounting_payment_batch_path(payment_batch))
    end

    it 'redirects with an alert when the batch is not generated' do
      payment_batch.update!(status: :draft)
      post execute_accounting_payment_batch_path(payment_batch)
      expect(response).to redirect_to(accounting_payment_batch_path(payment_batch))
      expect(flash[:alert]).to be_present
    end
  end

  describe 'GET /accounting/payment_batches/:id/download' do
    let(:payment_batch) do
      create(:payment_batch, :generated, bank_account: bank_account, sepa_xml: '<Document/>')
    end

    it 'streams the SEPA xml file' do
      get download_accounting_payment_batch_path(payment_batch)
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('<Document/>')
      expect(response.headers['Content-Type']).to include('application/xml')
    end
  end

  describe 'DELETE /accounting/payment_batches/:id' do
    context 'draft batch' do
      let!(:payment_batch) { create(:payment_batch, bank_account: bank_account, status: :draft) }

      it 'deletes and redirects to the index' do
        expect {
          delete accounting_payment_batch_path(payment_batch)
        }.to change(Accounting::PaymentBatch, :count).by(-1)
        expect(response).to redirect_to(accounting_payment_batches_path)
      end
    end

    context 'generated batch' do
      let!(:payment_batch) { create(:payment_batch, :generated, bank_account: bank_account) }

      it 'refuses and redirects back with an alert' do
        expect {
          delete accounting_payment_batch_path(payment_batch)
        }.not_to change(Accounting::PaymentBatch, :count)
        expect(response).to redirect_to(accounting_payment_batch_path(payment_batch))
      end
    end
  end

  describe 'authorization' do
    let(:payment_batch) { create(:payment_batch, bank_account: bank_account, status: :draft) }

    before { sign_in budget_user }

    it 'denies generate for a budget_user' do
      post generate_accounting_payment_batch_path(payment_batch)
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
