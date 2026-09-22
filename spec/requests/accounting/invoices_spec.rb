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

    describe 'filtres' do
      let!(:acme)   { create(:partner, name: 'ZZAcme') }
      let!(:globex) { create(:partner, name: 'ZZGlobex') }
      let!(:draft_inv)  { create(:invoice, :customer, partner: acme, fiscal_year: fiscal_year, invoice_date: Date.new(2025, 1, 5)) }
      let!(:posted_inv) { create(:invoice, :customer, :posted, partner: globex, fiscal_year: fiscal_year, invoice_date: Date.new(2025, 3, 5), due_date: Date.current - 5) }

      it 'filtre par nom de partenaire' do
        get accounting_sales_path, params: { q: { q: 'acme' } }
        expect(response.body).to include('ZZAcme').and not_include('ZZGlobex')
      end

      it 'filtre par statut' do
        get accounting_sales_path, params: { q: { status: 'posted' } }
        expect(response.body).to include('ZZGlobex').and not_include('ZZAcme')
      end

      it 'filtre par période' do
        get accounting_sales_path, params: { q: { from: '2025-02-01' } }
        expect(response.body).to include('ZZGlobex').and not_include('ZZAcme')
      end

      it 'filtre les factures échues' do
        get accounting_sales_path, params: { q: { overdue: '1' } }
        expect(response.body).to include('ZZGlobex').and not_include('ZZAcme')
      end

      it 'filtre les factures impayées côté achats' do
        create(:invoice, :supplier, :posted, partner: globex, fiscal_year: fiscal_year)
        create(:invoice, :supplier, partner: acme, fiscal_year: fiscal_year)
        get accounting_purchases_path, params: { q: { unpaid: '1' } }
        expect(response.body).to include('ZZGlobex').and not_include('ZZAcme')
      end
    end
  end

  describe 'GET /accounting/sales with column filters' do
    let!(:acme)   { create(:partner, name: 'ZZAcme') }
    let!(:globex) { create(:partner, name: 'ZZGlobex') }
    let!(:draft_inv)  { create(:invoice, :customer, partner: acme, fiscal_year: fiscal_year, invoice_date: Date.new(2025, 1, 5), total_incl_vat: 100) }
    let!(:posted_inv) { create(:invoice, :customer, :posted, partner: globex, fiscal_year: fiscal_year, invoice_date: Date.new(2025, 3, 5), total_incl_vat: 900) }

    it 'no longer duplicates status and date filters in the filter panel' do
      get accounting_sales_path
      expect(response.body).not_to include('name="q[status]"', 'name="q[from]"', 'name="q[to]"')
      expect(response.body).to include('name="q[q]"', 'name="q[unpaid]"', 'name="q[overdue]"')
    end

    it 'renders the column headers with filter dropdowns' do
      get accounting_sales_path
      expect(response.body).to include('data-controller="dropdown"').and include('Sort A')
    end

    it 'filters on a list of partner names' do
      get accounting_sales_path, params: { f: { partner: [ 'ZZAcme' ] } }
      expect(response.body).to include('ZZAcme').and not_include('ZZGlobex')
    end

    it 'filters on a status list and an amount range together' do
      get accounting_sales_path, params: { f: { status: %w[draft posted], total_incl_vat: { min: '500' } } }
      expect(response.body).to include('ZZGlobex').and not_include('ZZAcme')
    end

    it 'sorts by amount' do
      get accounting_sales_path, params: { sort: 'total_incl_vat', dir: 'desc' }
      expect(response.body.index('ZZGlobex')).to be < response.body.index('ZZAcme')
      get accounting_sales_path, params: { sort: 'total_incl_vat', dir: 'asc' }
      expect(response.body.index('ZZAcme')).to be < response.body.index('ZZGlobex')
    end

    it 'combines with the global search and keeps the empty table when nothing matches' do
      get accounting_sales_path, params: { q: { q: 'globex' }, f: { partner: [ 'ZZAcme' ] } }
      expect(response.body).not_to include('ZZGlobex')
      expect(response.body).to include('No results match your filters')
    end

    it 'ignores unknown columns and unknown sort keys' do
      get accounting_sales_path, params: { f: { bogus: %w[x] }, sort: 'bogus; DROP TABLE users' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('ZZAcme').and include('ZZGlobex')
    end

    it 'keeps column filters in the pagination links' do
      create_list(:invoice, 26, :customer, partner: acme, fiscal_year: fiscal_year)
      get accounting_sales_path, params: { f: { partner: [ 'ZZAcme' ] } }
      expect(response.body).to include('f%5Bpartner%5D%5B%5D=ZZAcme')
    end

    it 'shows a clear-all link when a column filter is active' do
      get accounting_sales_path, params: { f: { partner: [ 'ZZAcme' ] } }
      expect(response.body).to include('Clear all column filters')
    end
  end

  describe 'GET /accounting/column_values' do
    let!(:acme)   { create(:partner, name: 'ZZAcme') }
    let!(:globex) { create(:partner, name: 'ZZGlobex') }
    let!(:sale)     { create(:invoice, :customer, partner: acme, fiscal_year: fiscal_year) }
    let!(:purchase) { create(:invoice, :supplier, partner: globex, fiscal_year: fiscal_year) }

    it 'lists distinct values inside a matching turbo frame' do
      get accounting_column_values_path('invoices', 'partner')
      expect(response.body).to include('turbo-frame id="values-partner"').and include('ZZAcme').and include('ZZGlobex')
    end

    it 'checks the currently selected values' do
      get accounting_column_values_path('invoices', 'partner', f: { partner: [ 'ZZAcme' ] })
      expect(response.body).to match(/value="ZZAcme"\s+checked/)
    end

    it 'restricts to the invoice type of the calling page' do
      get accounting_column_values_path('invoices', 'partner', invoice_type: 'customer')
      expect(response.body).to include('ZZAcme').and not_include('ZZGlobex')
    end

    it '404s for an unknown resource and an empty list for an unknown column' do
      get accounting_column_values_path('users', 'email')
      expect(response).to have_http_status(:not_found)
      get accounting_column_values_path('invoices', 'nope')
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('No values')
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

    context 'avec des lignes (lines_attributes)' do
      let(:account) { create(:account) }

      it 'crée la facture ET ses lignes en une seule requête' do
        expect {
          post accounting_purchases_path, params: {
            accounting_invoice: {
              invoice_date: Date.current, partner_id: partner.id,
              fiscal_year_id: fiscal_year.id,
              lines_attributes: {
                '0' => { description: 'Fournitures', account_id: account.id,
                         quantity: '1', unit_price: '200.00', vat_rate: '21.00', position: '1' }
              }
            }
          }
        }.to change { Accounting::Invoice.supplier.count }.by(1)
          .and change { Accounting::InvoiceLine.count }.by(1)
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

  describe 'PATCH /accounting/invoices/:id — lignes imbriquées' do
    let(:invoice) { create(:invoice, :draft, :supplier, partner: partner, fiscal_year: fiscal_year) }
    let(:account) { create(:account) }

    it 'ajoute des lignes via lines_attributes' do
      expect {
        patch accounting_invoice_path(invoice), params: {
          accounting_invoice: {
            lines_attributes: {
              '0' => { description: 'Matériel', account_id: account.id,
                       quantity: '3', unit_price: '50.00', vat_rate: '21.00', position: '1' }
            }
          }
        }
      }.to change { invoice.lines.reload.count }.by(1)
    end

    it 'supprime une ligne existante via _destroy' do
      line = create(:invoice_line, invoice: invoice, account: account)
      expect {
        patch accounting_invoice_path(invoice), params: {
          accounting_invoice: {
            lines_attributes: { '0' => { id: line.id, _destroy: '1' } }
          }
        }
      }.to change { invoice.lines.reload.count }.by(-1)
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

    context 'customer invoice with a partial payment' do
      include_context 'with_pcmn_accounts'

      let!(:bank_journal) { create(:journal, :bank, default_account: account_550) }
      let(:bank_account)  { create(:bank_account, journal: bank_journal) }
      let(:customer_invoice) do
        create(:invoice, :customer, :posted, :with_lines, partner: partner, fiscal_year: fiscal_year)
          .tap { |i| i.update_columns(total_incl_vat: BigDecimal('1210')) }
      end

      before do
        tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('500'))
        Accounting::BookInvoiceReceipt.call(transaction: tx, invoice: customer_invoice, fiscal_year: fiscal_year)
      end

      it 'shows the amount paid and the remaining balance' do
        get accounting_invoice_path(customer_invoice)

        expect(response.body).to include('Paid').and include('Remaining')
        expect(response.body).to include(Accounting::MoneyPresenter.new(BigDecimal('500')).format)
        expect(response.body).to include(Accounting::MoneyPresenter.new(BigDecimal('710')).format)
      end

      it 'shows the overpayment once the invoice is overpaid' do
        tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('800'))
        Accounting::BookInvoiceReceipt.call(transaction: tx, invoice: customer_invoice, fiscal_year: fiscal_year)
        get accounting_invoice_path(customer_invoice)

        expect(response.body).to include('Overpaid')
        expect(response.body).to include(Accounting::MoneyPresenter.new(BigDecimal('90')).format)
      end

      it 'shows nothing for an invoice without payments' do
        other = create(:invoice, :customer, :posted, :with_lines, partner: partner, fiscal_year: fiscal_year)
        get accounting_invoice_path(other)

        expect(response.body).not_to include('Remaining')
      end

      it 'lists the receipt entry under "Journal entries"' do
        get accounting_invoice_path(customer_invoice)
        receipt_entry = customer_invoice.related_journal_entries.first

        expect(response.body).to include('Journal entries')
        expect(response.body).to include(receipt_entry.reference)
        expect(response.body).to include(accounting_journal_entry_path(receipt_entry))
      end
    end

    context 'invoice with no related journal entry' do
      it 'shows no "Journal entries" card' do
        draft_invoice = create(:invoice, :draft, partner: partner, fiscal_year: fiscal_year)
        get accounting_invoice_path(draft_invoice)

        expect(response.body).not_to include('Journal entries')
      end
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

  describe 'POST /accounting/invoices/:id/cancel_invoice' do
    include_context 'with_pcmn_accounts'

    let!(:purchase_journal) { create(:journal, :purchase) }
    let(:invoice) { create(:invoice, :with_lines, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal) }

    before { Accounting::PostInvoice.call(invoice: invoice) }

    it 'cancels a posted invoice and redirects to it' do
      post cancel_invoice_accounting_invoice_path(invoice)
      expect(invoice.reload).to be_cancelled
      expect(response).to redirect_to(accounting_invoice_path(invoice))
    end

    it 'redirects with an alert when the invoice cannot be cancelled' do
      invoice.update_columns(status: Accounting::Invoice.statuses[:paid])
      post cancel_invoice_accounting_invoice_path(invoice)
      expect(invoice.reload).to be_paid
      expect(flash[:alert]).to be_present
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

  describe 'cash journal on invoices' do
    let!(:cash_journal) { create(:journal, :cash) }
    let(:invoice)       { create(:invoice, :draft, :supplier, partner: partner, fiscal_year: fiscal_year) }

    it 'offers the cash journal select on the supplier form' do
      get accounting_new_purchases_path
      expect(response.body).to include('accounting_invoice_cash_journal_id', cash_journal.display_name)
    end

    it 'offers the cash journal select on the sales form too' do
      get accounting_new_sales_path
      expect(response.body).to include('accounting_invoice_cash_journal_id', cash_journal.display_name)
    end

    it 'saves the chosen cash journal on update' do
      patch accounting_invoice_path(invoice), params: { accounting_invoice: { cash_journal_id: cash_journal.id } }
      expect(invoice.reload.cash_journal).to eq(cash_journal)
    end
  end
end
