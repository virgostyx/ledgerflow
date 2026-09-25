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

    context 'avec un vat_treatment non-domestic' do
      let(:eu_partner) { create(:partner, vat_number: 'FR32123456789', country: 'FR') }

      it 'enregistre le vat_treatment' do
        post accounting_sales_path, params: {
          accounting_invoice: { invoice_date: Date.current, partner_id: eu_partner.id,
                                fiscal_year_id: fiscal_year.id, vat_treatment: 'intracom_services' }
        }
        expect(Accounting::Invoice.last.vat_treatment).to eq('intracom_services')
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

      it 'renders the receipt entry\'s accounting lines in a collapsible row' do
        get accounting_invoice_path(customer_invoice)
        receipt_entry = customer_invoice.related_journal_entries.first
        line = receipt_entry.lines.first

        expect(response.body).to include('data-controller="toggle"')
        expect(response.body).to include(line.account.code)
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

    %w[0 6 12 21].each do |rate|
      it "preselects the #{rate}% option for a line at #{rate}%" do
        create(:invoice_line, invoice: invoice, account: create(:account), quantity: 1, unit_price: '100.00',
               vat_rate: rate, position: 1)

        get edit_accounting_invoice_path(invoice)

        line_selects = Nokogiri::HTML(response.body).css("select[name$='[vat_rate]']").reject { |sel| sel.ancestors('template').any? }
        expect(line_selects.size).to eq(1)
        expect(line_selects.first.css('option[selected]').map { |o| o['value'] }).to eq([ format('%.2f', rate.to_f) ])
      end
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

  describe 'GET /accounting/invoices/:id/pdf' do
    include_context 'with_pcmn_accounts'

    let!(:sale_journal)     { create(:journal, :sale) }
    let!(:purchase_journal) { create(:journal, :purchase) }

    def posted(type, journal)
      inv = create(:invoice, :with_lines, invoice_type: type, fiscal_year: fiscal_year, journal: journal)
      Accounting::PostInvoice.call(invoice: inv).invoice.reload
    end

    it 'returns the invoice as a PDF, with a file name free of slashes' do
      invoice = posted(:customer, sale_journal)
      get pdf_accounting_invoice_path(invoice)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/pdf')
      expect(response.body).to start_with('%PDF')
      expect(response.headers['Content-Disposition']).to include(%(filename="#{invoice.invoice_number.tr('/', '-')}.pdf"))
    end

    it 'works for a credit note' do
      original = posted(:customer, sale_journal)
      note = original.build_credit_note.tap(&:save!)
      note = Accounting::PostInvoice.call(invoice: note).invoice.reload

      get pdf_accounting_invoice_path(note)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/pdf')
    end

    it 'refuses a draft' do
      draft = create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year, journal: sale_journal)
      get pdf_accounting_invoice_path(draft)

      expect(response).to redirect_to(accounting_invoice_path(draft))
      expect(flash[:alert]).to be_present
    end

    it 'refuses a cancelled invoice' do
      invoice = posted(:customer, sale_journal)
      invoice.update_columns(status: Accounting::Invoice.statuses[:cancelled])
      get pdf_accounting_invoice_path(invoice)

      expect(response).to redirect_to(accounting_invoice_path(invoice))
    end

    it 'refuses a supplier invoice' do
      invoice = posted(:supplier, purchase_journal)
      get pdf_accounting_invoice_path(invoice)

      expect(response).to redirect_to(accounting_invoice_path(invoice))
      expect(flash[:alert]).to be_present
    end

    it 'refuses a user who is not a member of the entity' do
      invoice = posted(:customer, sale_journal)
      sign_in create(:user)
      get pdf_accounting_invoice_path(invoice)

      expect(response).not_to have_http_status(:ok)
    end

    describe 'the download button' do
      it 'shows on a posted customer invoice' do
        get accounting_invoice_path(posted(:customer, sale_journal))
        expect(response.body).to include('Download PDF')
      end

      it 'is absent on a draft and on a supplier invoice' do
        draft = create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year, journal: sale_journal)
        get accounting_invoice_path(draft)
        expect(response.body).not_to include('Download PDF')

        get accounting_invoice_path(posted(:supplier, purchase_journal))
        expect(response.body).not_to include('Download PDF')
      end
    end
  end

  describe 'e-mailing an invoice' do
    include_context 'with_pcmn_accounts'

    let!(:sale_journal)     { create(:journal, :sale) }
    let!(:purchase_journal) { create(:journal, :purchase) }

    around do |example|
      previous = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      example.run
    ensure
      ActiveJob::Base.queue_adapter = previous
    end

    def posted(type, journal, partner_email: nil)
      inv = create(:invoice, :with_lines, invoice_type: type, fiscal_year: fiscal_year, journal: journal,
                   partner: create(:partner, email: partner_email))
      Accounting::PostInvoice.call(invoice: inv).invoice.reload
    end

    describe 'POST /accounting/invoices/:id/send_email' do
      it 'queues the e-mail and goes back to the invoice with a notice' do
        invoice = posted(:customer, sale_journal)

        expect { post send_email_accounting_invoice_path(invoice), params: { recipient: 'accounts@client.example' } }
          .to change(Accounting::InvoiceEmail, :count).by(1)
          .and have_enqueued_job(Accounting::InvoiceEmailJob)

        expect(response).to redirect_to(accounting_invoice_path(invoice))
        expect(flash[:notice]).to include('accounts@client.example')
        expect(Accounting::InvoiceEmail.last).to have_attributes(recipient: 'accounts@client.example', sent_by: accountant,
                                                                 status: 'queued')
      end

      it 'refuses an invalid recipient with an alert' do
        invoice = posted(:customer, sale_journal)

        expect { post send_email_accounting_invoice_path(invoice), params: { recipient: 'nope' } }
          .not_to change(Accounting::InvoiceEmail, :count)

        expect(response).to redirect_to(accounting_invoice_path(invoice))
        expect(flash[:alert]).to be_present
      end

      it 'refuses a draft and a supplier invoice' do
        draft = create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year, journal: sale_journal)
        post send_email_accounting_invoice_path(draft), params: { recipient: 'a@b.example' }
        expect(flash[:alert]).to be_present

        supplier = posted(:supplier, purchase_journal)
        post send_email_accounting_invoice_path(supplier), params: { recipient: 'a@b.example' }
        expect(flash[:alert]).to be_present
        expect(Accounting::InvoiceEmail.count).to eq(0)
      end

      it 'is refused to a user who cannot post invoices' do
        invoice = posted(:customer, sale_journal)
        sign_in create(:user, role: :auditor).tap { |u| create(:user_entity, :auditor, user: u, entity: entity) }

        post send_email_accounting_invoice_path(invoice), params: { recipient: 'a@b.example' }

        expect(Accounting::InvoiceEmail.count).to eq(0)
        expect(response).not_to have_http_status(:ok)
      end
    end

    describe 'the e-mail card on the invoice page' do
      it 'offers a form prefilled with the partner e-mail' do
        get accounting_invoice_path(posted(:customer, sale_journal, partner_email: 'billing@partner.example'))

        expect(response.body).to include('Send by email')
        expect(response.body).to include('value="billing@partner.example"')
      end

      it 'lists past attempts with their status and error' do
        invoice = posted(:customer, sale_journal)
        create(:invoice_email, :sent, invoice: invoice, recipient: 'ok@client.example')
        create(:invoice_email, :failed, invoice: invoice, recipient: 'ko@client.example', error: 'Connection refused')

        get accounting_invoice_path(invoice)

        expect(response.body).to include('ok@client.example', 'ko@client.example', 'Connection refused')
      end

      it 'is absent on a draft and on a supplier invoice' do
        draft = create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year, journal: sale_journal)
        get accounting_invoice_path(draft)
        expect(response.body).not_to include('Send by email')

        get accounting_invoice_path(posted(:supplier, purchase_journal))
        expect(response.body).not_to include('Send by email')
      end
    end
  end

  describe 'VAT treatment help on the invoice form' do
    TREATMENTS = Accounting::Invoice.vat_treatments.keys.freeze

    def help(treatment, type) = I18n.t("accounting.invoices.vat_treatment_help.#{treatment}.#{type}")

    def help_paragraphs
      Nokogiri::HTML(response.body).css('[data-invoice-form-target="treatmentHelp"] p[data-treatment]')
    end

    it 'explains every treatment for a sale, in customer wording' do
      get accounting_new_sales_path

      TREATMENTS.each { |t| expect(response.body).to include(ERB::Util.html_escape(help(t, 'customer'))) }
      expect(response.body).not_to include('translation missing')
    end

    it 'explains every treatment for a purchase, in supplier wording' do
      get accounting_new_purchases_path

      TREATMENTS.each { |t| expect(response.body).to include(ERB::Util.html_escape(help(t, 'supplier'))) }
      expect(response.body).not_to include('translation missing')
    end

    it 'does not mix the wording of sales and purchases' do
      get accounting_new_sales_path
      TREATMENTS.each { |t| expect(response.body).not_to include(ERB::Util.html_escape(help(t, 'supplier'))) }

      get accounting_new_purchases_path
      TREATMENTS.each { |t| expect(response.body).not_to include(ERB::Util.html_escape(help(t, 'customer'))) }
    end

    it 'shows only the explanation of the selected treatment when the page loads' do
      get accounting_new_sales_path

      visible = help_paragraphs.reject { |p| p['class'].to_s.split.include?('hidden') }.map { |p| p['data-treatment'] }
      expect(visible).to eq([ 'domestic' ])
    end

    it 'shows the explanation of the treatment of a saved draft' do
      partner = create(:partner, vat_number: 'FR32123456789', country: 'FR')
      draft = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year, vat_treatment: :intracom_services)
      get edit_accounting_invoice_path(draft)

      visible = help_paragraphs.reject { |p| p['class'].to_s.split.include?('hidden') }.map { |p| p['data-treatment'] }
      expect(visible).to eq([ 'intracom_services' ])
    end

    it 'tells the user which treatments need a VAT number of the partner' do
      %w[intracom_goods intracom_services construction_reverse_charge].each do |t|
        expect(help(t, 'customer')).to include('VAT number')
        expect(help(t, 'supplier')).to include('VAT number')
      end
    end
  end

  describe 'credit notes' do
    include_context 'with_pcmn_accounts'

    let!(:sale_journal) { create(:journal, :sale) }
    let(:original) do
      inv = create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year, journal: sale_journal)
      Accounting::PostInvoice.call(invoice: inv).invoice.reload
    end

    describe 'POST /accounting/invoices/:id/create_credit_note' do
      it 'creates a draft credit note prefilled from the invoice and opens it for editing' do
        expect { post create_credit_note_accounting_invoice_path(original) }
          .to change(Accounting::Invoice.credit_note, :count).by(1)

        note = Accounting::Invoice.credit_note.last
        expect(response).to redirect_to(edit_accounting_invoice_path(note))
        expect(note).to be_draft
        expect(note.credited_invoice).to eq(original)
        expect(note).to have_attributes(partner: original.partner, invoice_type: 'customer',
                                        currency: original.currency, vat_treatment: original.vat_treatment)
        expect(note.lines.map { |l| [ l.description, l.unit_price, l.vat_rate ] })
          .to eq(original.lines.map { |l| [ l.description, l.unit_price, l.vat_rate ] })
      end

      it 'refuses a draft invoice' do
        draft = create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year)
        expect { post create_credit_note_accounting_invoice_path(draft) }
          .not_to change(Accounting::Invoice, :count)
        expect(flash[:alert]).to be_present
      end
    end

    describe 'POST /accounting/invoices/:id/apply_credit_note' do
      let(:note) do
        n = create(:invoice, invoice_type: :customer, partner: original.partner, fiscal_year: fiscal_year,
                   journal: sale_journal, document_type: :credit_note, credited_invoice: original)
        create(:invoice_line, invoice: n, account: original.lines.first.account, quantity: 1,
               unit_price: '400.00', vat_rate: '21.00', position: 1)
        Accounting::PostInvoice.call(invoice: n).invoice.reload
      end

      it 'settles the credit note against its invoice and redirects to the credit note' do
        post apply_credit_note_accounting_invoice_path(note)

        expect(response).to redirect_to(accounting_invoice_path(note))
        expect(flash[:notice]).to be_present
        expect(original.reload).to be_partially_paid
        expect(note.reload).to be_paid
      end

      it 'redirects with an alert when it cannot be applied' do
        note.update_columns(credited_invoice_id: nil)
        post apply_credit_note_accounting_invoice_path(note)
        expect(flash[:alert]).to be_present
      end
    end

    describe 'GET /accounting/invoices/:id' do
      it 'offers "Create credit note" on a posted invoice' do
        get accounting_invoice_path(original)
        expect(response.body).to include('Create credit note')
      end

      it 'offers "Apply to invoice" and labels a posted credit note' do
        n = create(:invoice, invoice_type: :customer, partner: original.partner, fiscal_year: fiscal_year,
                   journal: sale_journal, document_type: :credit_note, credited_invoice: original)
        create(:invoice_line, invoice: n, account: original.lines.first.account, quantity: 1,
               unit_price: '100.00', vat_rate: '21.00', position: 1)
        n = Accounting::PostInvoice.call(invoice: n).invoice.reload

        get accounting_invoice_path(n)
        expect(response.body).to include('Apply to invoice')
        expect(response.body).to include('Credit note')
        expect(response.body).not_to include('Create credit note')
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
