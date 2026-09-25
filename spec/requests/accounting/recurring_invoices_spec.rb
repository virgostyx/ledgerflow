require 'rails_helper'

RSpec.describe 'Accounting::RecurringInvoices', type: :request do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let(:accountant) { create(:user, role: :accountant) }
  let(:auditor)    { create(:user, role: :auditor) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:auditor_membership)    { create(:user_entity, :auditor, user: auditor, entity: entity) }
  let!(:sale_journal) { create(:journal, :sale) }
  let(:partner) { create(:partner, name: 'Retainer client') }

  before { sign_in accountant }

  let(:source) do
    inv = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year, journal: sale_journal,
                 invoice_date: Date.new(2026, 1, 31), due_date: Date.new(2026, 2, 28))
    create(:invoice_line, invoice: inv, account: account_700, unit_price: '500.00', vat_rate: '21.00', position: 1)
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end

  describe 'GET /accounting/recurring_invoices/new' do
    it 'shows the source invoice and a first date one period after it' do
      get new_accounting_recurring_invoice_path(invoice_id: source.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(source.invoice_number, 'Retainer client')
      expect(Nokogiri::HTML(response.body).at_css('input[name="accounting_recurring_invoice[start_on]"]')['value']).to eq('2026-02-28')
    end

    it 'refuses a draft with an alert' do
      draft = create(:invoice, fiscal_year: fiscal_year)
      get new_accounting_recurring_invoice_path(invoice_id: draft.id)

      expect(response).to redirect_to(accounting_recurring_invoices_path)
      expect(flash[:alert]).to be_present
    end

    it 'refuses a credit note' do
      note = create(:invoice, :posted, fiscal_year: fiscal_year, document_type: :credit_note)
      get new_accounting_recurring_invoice_path(invoice_id: note.id)

      expect(response).to redirect_to(accounting_recurring_invoices_path)
    end

    it 'refuses a missing or unknown invoice' do
      get new_accounting_recurring_invoice_path
      expect(response).to redirect_to(accounting_recurring_invoices_path)

      get new_accounting_recurring_invoice_path(invoice_id: 0)
      expect(response).to redirect_to(accounting_recurring_invoices_path)
    end
  end

  describe 'POST /accounting/recurring_invoices' do
    let(:attrs) { { source_invoice_id: source.id, frequency: 'quarterly', start_on: '2026-04-30', end_on: '2027-04-30' } }

    it 'creates the recurring invoice and goes to the list' do
      expect { post accounting_recurring_invoices_path, params: { accounting_recurring_invoice: attrs } }
        .to change(Accounting::RecurringInvoice, :count).by(1)

      expect(response).to redirect_to(accounting_recurring_invoices_path)
      expect(flash[:notice]).to be_present
      expect(Accounting::RecurringInvoice.last).to have_attributes(source_invoice: source, frequency: 'quarterly',
                                                                   start_on: Date.new(2026, 4, 30), end_on: Date.new(2027, 4, 30), active: true)
    end

    it 'returns 422 when the end date is before the first date' do
      expect { post accounting_recurring_invoices_path, params: { accounting_recurring_invoice: attrs.merge(end_on: '2026-01-01') } }
        .not_to change(Accounting::RecurringInvoice, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 for a draft as source' do
      draft = create(:invoice, fiscal_year: fiscal_year)
      post accounting_recurring_invoices_path, params: { accounting_recurring_invoice: attrs.merge(source_invoice_id: draft.id) }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'is refused to a read-only auditor' do
      sign_in auditor
      expect { post accounting_recurring_invoices_path, params: { accounting_recurring_invoice: attrs } }
        .not_to change(Accounting::RecurringInvoice, :count)
    end
  end

  describe 'GET /accounting/recurring_invoices' do
    it 'lists the recurrences with their source, schedule and status' do
      create(:recurring_invoice, source_invoice: source, frequency: :quarterly, start_on: Date.new(2026, 4, 30))
      get accounting_recurring_invoices_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(source.invoice_number, 'Retainer client', 'Quarterly', '30/04/2026', 'Active')
    end

    it 'shows the last error, and how many generated drafts wait for review' do
      rec = create(:recurring_invoice, source_invoice: source, last_error: 'No fiscal year is open', start_on: Date.new(2026, 4, 30))
      create(:invoice, fiscal_year: fiscal_year, recurring_invoice: rec)
      get accounting_recurring_invoices_path

      expect(response.body).to include('No fiscal year is open', '1 draft to review')
    end

    it 'shows paused and ended recurrences as such' do
      create(:recurring_invoice, source_invoice: source, active: false)
      create(:recurring_invoice, source_invoice: source, start_on: Date.new(2026, 1, 1), end_on: Date.new(2026, 1, 31), runs_count: 1)
      get accounting_recurring_invoices_path

      expect(response.body).to include('Paused', 'Ended')
    end

    it 'says so when there is none yet' do
      get accounting_recurring_invoices_path
      expect(response.body).to include('No recurring invoices yet')
    end
  end

  describe 'PATCH /accounting/recurring_invoices/:id' do
    let!(:rec) { create(:recurring_invoice, source_invoice: source, start_on: Date.new(2026, 1, 1)) }

    it 'pauses it' do
      patch accounting_recurring_invoice_path(rec), params: { accounting_recurring_invoice: { active: 'false' } }

      expect(response).to redirect_to(accounting_recurring_invoices_path)
      expect(rec.reload).not_to be_active
    end

    it 'resumes it without letting the paused period catch up' do
      rec.update!(active: false)
      patch accounting_recurring_invoice_path(rec), params: { accounting_recurring_invoice: { active: 'true' } }

      expect(rec.reload).to be_active
      expect(rec.next_run_on).to be >= Date.current
    end

    it 'sets an end date' do
      patch accounting_recurring_invoice_path(rec), params: { accounting_recurring_invoice: { end_on: '2026-12-31' } }
      expect(rec.reload.end_on).to eq(Date.new(2026, 12, 31))
    end

    it 'does not let the schedule itself be changed' do
      patch accounting_recurring_invoice_path(rec), params: { accounting_recurring_invoice: { frequency: 'yearly', start_on: '2030-01-01', runs_count: 9 } }

      expect(rec.reload).to have_attributes(frequency: 'monthly', start_on: Date.new(2026, 1, 1), runs_count: 0)
    end
  end

  describe 'DELETE /accounting/recurring_invoices/:id' do
    it 'removes the recurrence and keeps the drafts it generated' do
      rec = create(:recurring_invoice, source_invoice: source)
      draft = create(:invoice, fiscal_year: fiscal_year, recurring_invoice: rec)

      expect { delete accounting_recurring_invoice_path(rec) }.to change(Accounting::RecurringInvoice, :count).by(-1)

      expect(response).to redirect_to(accounting_recurring_invoices_path)
      expect(draft.reload.recurring_invoice).to be_nil
    end

    it 'is refused to a read-only auditor' do
      rec = create(:recurring_invoice, source_invoice: source)
      sign_in auditor

      expect { delete accounting_recurring_invoice_path(rec) }.not_to change(Accounting::RecurringInvoice, :count)
    end
  end

  describe 'on the invoice page' do
    it 'offers Make recurring on an issued invoice' do
      get accounting_invoice_path(source)
      expect(response.body).to include('Make recurring', new_accounting_recurring_invoice_path(invoice_id: source.id))
    end

    it 'offers nothing on a draft, a credit note or to an auditor' do
      draft = create(:invoice, fiscal_year: fiscal_year)
      get accounting_invoice_path(draft)
      expect(response.body).not_to include('Make recurring')

      note = create(:invoice, :posted, fiscal_year: fiscal_year, document_type: :credit_note)
      get accounting_invoice_path(note)
      expect(response.body).not_to include('Make recurring')

      sign_in auditor
      get accounting_invoice_path(source)
      expect(response.body).not_to include('Make recurring')
    end

    it 'tells that a generated draft comes from a recurring invoice' do
      rec = create(:recurring_invoice, source_invoice: source)
      draft = create(:invoice, fiscal_year: fiscal_year, recurring_invoice: rec)
      get accounting_invoice_path(draft)

      expect(response.body).to include('Generated from a recurring invoice', accounting_recurring_invoices_path)
    end
  end

  describe 'the menu' do
    it 'links to the recurring invoices' do
      get accounting_root_path
      expect(response.body).to include(accounting_recurring_invoices_path)
    end
  end
end
