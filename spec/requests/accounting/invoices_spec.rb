require 'rails_helper'

RSpec.describe 'Accounting::Invoices', type: :request do
  include_context 'with_open_fiscal_year'

  let(:accountant) { create(:user, role: :accountant) }
  let(:admin)      { create(:user, role: :admin) }
  let(:partner)    { create(:partner) }

  before { sign_in accountant }

  describe 'GET /accounting/invoices' do
    it 'retourne 200' do
      get accounting_invoices_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounting/invoices/new' do
    it 'retourne 200' do
      get new_accounting_invoice_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /accounting/invoices' do
    context 'avec des attributs valides' do
      let(:valid_attrs) do
        { invoice_type: 'customer', invoice_date: Date.current,
          partner_id: partner.id, fiscal_year_id: fiscal_year.id }
      end

      it 'crée une facture' do
        expect {
          post accounting_invoices_path, params: { accounting_invoice: valid_attrs }
        }.to change(Accounting::Invoice, :count).by(1)
      end

      it 'redirige vers la facture' do
        post accounting_invoices_path, params: { accounting_invoice: valid_attrs }
        expect(response).to redirect_to(accounting_invoice_path(Accounting::Invoice.last))
      end
    end

    context 'sans date' do
      it 'retourne 422' do
        post accounting_invoices_path, params: {
          accounting_invoice: { invoice_type: 'customer', partner_id: partner.id }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'GET /accounting/invoices/:id' do
    let(:invoice) { create(:invoice, partner: partner, fiscal_year: fiscal_year) }

    it 'retourne 200' do
      get accounting_invoice_path(invoice)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounting/invoices/:id/edit' do
    let(:invoice) { create(:invoice, :draft, partner: partner, fiscal_year: fiscal_year) }

    it 'retourne 200' do
      get edit_accounting_invoice_path(invoice)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /accounting/invoices/:id' do
    let(:invoice) { create(:invoice, :draft, partner: partner, fiscal_year: fiscal_year) }

    context 'avec des attributs valides' do
      it 'met à jour la facture et redirige' do
        patch accounting_invoice_path(invoice), params: {
          accounting_invoice: { due_date: Date.current + 60 }
        }
        expect(response).to redirect_to(accounting_invoice_path(invoice))
      end
    end
  end

  describe 'POST /accounting/invoices/:id/validate_invoice' do
    include_context 'with_pcmn_accounts'

    let!(:sale_journal) { create(:journal, :sale) }
    let(:invoice)       { create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year) }

    it 'valide la facture et redirige' do
      post validate_invoice_accounting_invoice_path(invoice)
      expect(invoice.reload).to be_posted
      expect(response).to redirect_to(accounting_invoice_path(invoice))
    end
  end

  describe 'DELETE /accounting/invoices/:id' do
    context 'facture brouillon' do
      let!(:invoice) { create(:invoice, :draft, partner: partner, fiscal_year: fiscal_year) }

      it 'supprime et redirige' do
        expect {
          delete accounting_invoice_path(invoice)
        }.to change(Accounting::Invoice, :count).by(-1)
        expect(response).to redirect_to(accounting_invoices_path)
      end
    end

    context 'facture validée' do
      let!(:invoice) { create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year) }

      it 'refuse (422)' do
        delete accounting_invoice_path(invoice)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
