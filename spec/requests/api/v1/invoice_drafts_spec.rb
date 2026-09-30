require 'rails_helper'

# Draft mode (post: false): BudgetFlow invoices arrive as drafts the accountant codes and posts in LedgerFlow.
RSpec.describe 'Api::V1 invoice drafts', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'BF-P-1') }
  let(:issued)    { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[invoices:read invoices:write]) }
  let(:headers)   { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:line)      { { account_code: '604000', description: 'Consulting', quantity: '2', unit_price: '50.00', vat_rate: '21' } }
  let(:payload) do
    { partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s, post: false, lines: [ line ] }
  end

  def put_invoice(body = payload, ref: 'BF-I-1') = put("/api/v1/invoices/#{ref}", params: body, headers: headers, as: :json)
  def json = JSON.parse(response.body)
  def invoice(ref = 'BF-I-1') = Accounting::Invoice.external.find_by(external_ref: ref)

  describe 'post: false' do
    it 'creates a draft: no entry, no number, totals computed' do
      expect { put_invoice }.not_to change(Accounting::JournalEntry, :count)

      expect(response).to have_http_status(:created)
      expect(invoice).to have_attributes(status: 'draft', invoice_number: nil, journal_entry: nil, revision: 1,
                                         subtotal_excl_vat: BigDecimal('100'), vat_amount: BigDecimal('21'),
                                         total_incl_vat: BigDecimal('121'))
      expect(json).to include('status' => 'draft', 'invoice_number' => nil)
    end

    it 'is idempotent' do
      put_invoice
      put_invoice

      expect(response).to have_http_status(:ok)
      expect(Accounting::Invoice.external.where(external_ref: 'BF-I-1').count).to eq(1)
    end

    it 'still posts straight away when post is absent (other API clients)' do
      put_invoice(payload.except(:post))

      expect(response).to have_http_status(:created)
      expect(invoice).to be_posted
    end

    it 'can then be posted by the accountant with the regular service' do
      put_invoice

      result = Accounting::PostInvoice.call(invoice: invoice)

      expect(result).to be_success
      expect(invoice.reload).to be_posted
      expect(invoice.journal_entry).to be_posted
    end
  end
end
