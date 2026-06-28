require 'rails_helper'

RSpec.describe 'Accounting::Invoices', type: :request do
  include_context 'with_open_fiscal_year'

  let(:accountant) { create(:user, role: :accountant) }
  let(:admin)      { create(:user, role: :admin) }
  let(:partner)    { create(:partner) }

  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:admin_membership)      { create(:user_entity, :admin,      user: admin,      entity: entity) }

  before { sign_in accountant }

  # ---------------------------------------------------------------------------
  # Sales (customer invoices)
  # ---------------------------------------------------------------------------

  describe 'GET /accounting/sales' do
    it 'retourne 200' do
      get accounting_sales_path
      expect(response).to have_http_status(:ok)
    end

    it 'affiche uniquement les factures client' do
      customer_partner = create(:partner)
      supplier_partner = create(:partner)
      create(:invoice, :customer, partner: customer_partner, fiscal_year: fiscal_year)
      create(:invoice, :supplier, partner: supplier_partner, fiscal_year: fiscal_year)

      get accounting_sales_path

      expect(response.body).to include(customer_partner.name)
      expect(response.body).not_to include(supplier_partner.name)
    end
  end

  describe 'GET /accounting/sales/new' do
    it 'retourne 200' do
      get accounting_new_sales_path
      expect(response).to have_http_status(:ok)
    end

    it "n'affiche pas le champ invoice_type" do
      get accounting_new_sales_path
      expect(response.body).not_to include('name="accounting_invoice[invoice_type]"')
    end
  end

  describe 'POST /accounting/sales' do
    context 'avec des attributs valides' do
      let(:valid_attrs) do
        { invoice_date: Date.current, partner_id: partner.id, fiscal_year_id: fiscal_year.id }
      end

      it 'crée une facture client' do
        expect {
          post accounting_sales_path, params: { accounting_invoice: valid_attrs }
        }.to change { Accounting::Invoice.customer.count }.by(1)
      end

      it 'redirige vers la facture créée' do
        post accounting_sales_path, params: { accounting_invoice: valid_attrs }
        expect(response).to redirect_to(accounting_invoice_path(Accounting::Invoice.last))
      end
    end

    context 'sans date' do
      it 'retourne 422' do
        post accounting_sales_path, params: {
          accounting_invoice: { partner_id: partner.id }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Purchases (supplier invoices)
  # ---------------------------------------------------------------------------

  describe 'GET /accounting/purchases' do
    it 'retourne 200' do
      get accounting_purchases_path
      expect(response).to have_http_status(:ok)
    end

    it 'affiche uniquement les factures fournisseur' do
      customer_partner = create(:partner)
      supplier_partner = create(:partner)
      create(:invoice, :customer, partner: customer_partner, fiscal_year: fiscal_year)
      create(:invoice, :supplier, partner: supplier_partner, fiscal_year: fiscal_year)

      get accounting_purchases_path

      expect(response.body).to include(supplier_partner.name)
      expect(response.body).not_to include(customer_partner.name)
    end

    it 'affiche le bouton Delete pour les factures fournisseur en brouillon' do
      create(:invoice, :draft, :supplier, partner: partner, fiscal_year: fiscal_year)
      get accounting_purchases_path
      expect(response.body).to include('Delete')
    end

    it "n'affiche pas le bouton Delete pour les factures fournisseur validées" do
      create(:invoice, :posted, :supplier, partner: partner, fiscal_year: fiscal_year)
      get accounting_purchases_path
      expect(response.body).not_to include('Delete')
    end
  end

  describe 'GET /accounting/purchases/new' do
    it 'retourne 200' do
      get accounting_new_purchases_path
      expect(response).to have_http_status(:ok)
    end

    it "n'affiche pas le champ invoice_type" do
      get accounting_new_purchases_path
      expect(response.body).not_to include('name="accounting_invoice[invoice_type]"')
    end

    context 'avec un journal achats existant' do
      let!(:purchase_journal) { create(:journal, :purchase) }

      it 'pré-sélectionne le journal achats par défaut' do
        get accounting_new_purchases_path
        expect(response.body).to include('selected')
        expect(response.body).to include(purchase_journal.code)
      end
    end
  end

  describe 'POST /accounting/purchases' do
    context 'avec des attributs valides' do
      let(:valid_attrs) do
        { invoice_date: Date.current, partner_id: partner.id, fiscal_year_id: fiscal_year.id }
      end

      it 'crée une facture fournisseur' do
        expect {
          post accounting_purchases_path, params: { accounting_invoice: valid_attrs }
        }.to change { Accounting::Invoice.supplier.count }.by(1)
      end

      it 'redirige vers la facture créée' do
        post accounting_purchases_path, params: { accounting_invoice: valid_attrs }
        expect(response).to redirect_to(accounting_invoice_path(Accounting::Invoice.last))
      end
    end

    context 'sans date' do
      it 'retourne 422' do
        post accounting_purchases_path, params: {
          accounting_invoice: { partner_id: partner.id }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Individual invoice actions (routes inchangées)
  # ---------------------------------------------------------------------------

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

    context 'facture client' do
      let!(:sale_journal) { create(:journal, :sale) }
      let(:invoice)       { create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year, journal: sale_journal) }

      it 'valide la facture et redirige' do
        post validate_invoice_accounting_invoice_path(invoice)
        expect(invoice.reload).to be_posted
        expect(response).to redirect_to(accounting_invoice_path(invoice))
      end
    end

    context 'facture fournisseur' do
      let!(:purchase_journal) { create(:journal, :purchase) }
      let(:invoice) { create(:invoice, :with_lines, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal) }

      it 'valide la facture fournisseur et utilise le journal sélectionné' do
        post validate_invoice_accounting_invoice_path(invoice)
        expect(invoice.reload).to be_posted
        expect(invoice.reload.journal_entry.journal).to eq(purchase_journal)
      end
    end
  end

  describe 'POST /accounting/invoices/:id/send_peppol' do
    context 'facture validée (posted)' do
      let(:invoice) do
        inv = create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year,
                     invoice_number: "VTE2025/0001", invoice_date: Date.current)
        account = create(:account, code: "700000")
        create(:invoice_line, invoice: inv, account: account,
               description: "Service", quantity: 1, unit_price: "100.00", vat_rate: "21.00", position: 1)
        inv.compute_totals; inv.save!
        inv
      end

      before do
        stub_request(:post, %r{#{Regexp.escape(DIGITEAL_API_URL)}/api/invoices})
          .to_return(
            status: 201,
            body: { 'id' => 'PEPPOL-TEST-001', 'status' => 'queued' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'envoie la facture et redirige' do
        post send_peppol_accounting_invoice_path(invoice)
        expect(response).to redirect_to(accounting_invoice_path(invoice))
      end

      it 'met à jour peppol_status' do
        post send_peppol_accounting_invoice_path(invoice)
        expect(invoice.reload.peppol_status).to eq('queued')
      end
    end

    context 'facture brouillon' do
      let!(:invoice) { create(:invoice, :draft, partner: partner, fiscal_year: fiscal_year) }

      it 'redirige avec alerte' do
        post send_peppol_accounting_invoice_path(invoice)
        expect(response).to redirect_to(accounting_invoice_path(invoice))
      end
    end
  end

  describe 'DELETE /accounting/invoices/:id' do
    context 'facture client brouillon' do
      let!(:invoice) { create(:invoice, :draft, :customer, partner: partner, fiscal_year: fiscal_year) }

      it 'supprime et redirige vers Sales' do
        expect {
          delete accounting_invoice_path(invoice)
        }.to change(Accounting::Invoice, :count).by(-1)
        expect(response).to redirect_to(accounting_sales_path)
      end
    end

    context 'facture fournisseur brouillon' do
      let!(:invoice) { create(:invoice, :draft, :supplier, partner: partner, fiscal_year: fiscal_year) }

      it 'supprime et redirige vers Purchases' do
        expect {
          delete accounting_invoice_path(invoice)
        }.to change(Accounting::Invoice, :count).by(-1)
        expect(response).to redirect_to(accounting_purchases_path)
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
