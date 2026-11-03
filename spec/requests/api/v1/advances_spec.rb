require 'rails_helper'

# An advance to a supplier is the same resource as an invoice (document_type "advance", docs/dev/api/inbound-api.md §4.6): booked on 409000 until
# invoices settle it (advance_refs), which moves the amount from the supplier account to 409000.
RSpec.describe 'Api::V1 advances', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:account_409) { create(:account, code: '409000', label_fr: 'Avances versées', reconcilable: true, entity: entity) }
  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'BF-P-1') }
  let(:issued)    { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[invoices:read invoices:write]) }
  let(:headers)   { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:advance_line) { { description: 'Advance', quantity: '1', unit_price: '100.00', vat_rate: '0' } }
  let(:advance_payload) do
    { document_type: 'advance', partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s, lines: [ advance_line ] }
  end
  let(:invoice_line) { { account_code: '604000', description: 'Consulting', quantity: '1', unit_price: '100.00', vat_rate: '21' } } # 121 incl. VAT
  let(:advance_refs) { [ { invoice_ref: 'BF-A-1', amount: '100.00' } ] }
  let(:invoice_payload) do
    { partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s, lines: [ invoice_line ], advance_refs: advance_refs }
  end

  def put_doc(ref, body) = put("/api/v1/invoices/#{ref}", params: body, headers: headers, as: :json)
  def json = JSON.parse(response.body)
  def doc(ref) = Accounting::Invoice.external.where(external_ref: ref).order(:revision)
  def balance(code) = Accounting::JournalEntryLine.joins(:account).where(accounting_accounts: { code: code }).sum('debit - credit')

  describe 'an advance' do
    it 'is booked on 409000 against the supplier account, without VAT' do
      put_doc('BF-A-1', advance_payload)

      expect(response).to have_http_status(:created)
      advance = doc('BF-A-1').first
      expect(advance).to have_attributes(document_type: 'advance', status: 'posted', total_incl_vat: BigDecimal('100'))
      expect(advance.journal_entry.lines.map { |l| [ l.account.code, l.debit, l.credit ] })
        .to contain_exactly([ '409000', 100, 0 ], [ '440000', 0, 100 ])
      expect(json).to include('document_type' => 'advance')
    end

    it 'is idempotent' do
      put_doc('BF-A-1', advance_payload)
      expect { put_doc('BF-A-1', advance_payload) }.not_to change(Accounting::Invoice, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'refuses, with 422, VAT on an advance and any account but 409000' do
      advance_line[:vat_rate] = '21'
      put_doc('BF-A-1', advance_payload)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors'].values.flatten.join).to match(/vat/i)

      advance_line.merge!(vat_rate: '0', account_code: '604000')
      put_doc('BF-A-1', advance_payload)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors'].values.flatten.join).to include('409000')
    end

    it 'says so, with 422, when 409000 is not in the chart of the entity' do
      account_409.destroy!

      expect { put_doc('BF-A-1', advance_payload) }.not_to change(Accounting::Invoice, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors'].values.flatten.join).to include('409000')
    end

    it 'refuses advance_refs on anything but an invoice' do
      put_doc('BF-A-1', advance_payload)
      put_doc('BF-A-2', advance_payload.merge(advance_refs: advance_refs))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['advance_refs'].first).to match(/only allowed on an invoice/)
    end
  end

  describe 'an invoice that settles an advance' do
    before { put_doc('BF-A-1', advance_payload) }

    it 'moves the amount from the supplier account to 409000 and is partially paid' do
      put_doc('BF-I-1', invoice_payload)

      expect(response).to have_http_status(:created), response.body
      invoice = doc('BF-I-1').first
      expect(invoice).to be_partially_paid
      expect(invoice.remaining_amount).to eq(BigDecimal('21'))
      allocation = invoice.advance_allocations.first
      expect(allocation.journal_entry.lines.map { |l| [ l.account.code, l.debit, l.credit ] })
        .to contain_exactly([ '440000', 100, 0 ], [ '409000', 0, 100 ])
      expect(balance('409000')).to eq(0)
      expect(json['advance_refs']).to eq([ { 'invoice_ref' => 'BF-A-1', 'amount' => '100.0' } ])
    end

    it 'is paid when the advance covers all of it' do
      invoice_line.merge!(unit_price: '100.00', vat_rate: '0')
      put_doc('BF-I-1', invoice_payload)

      expect(doc('BF-I-1').first).to be_paid
      expect(doc('BF-A-1').first.advance_remaining).to eq(0)
      expect(Accounting::JournalEntryLine.joins(:account).where(accounting_accounts: { code: '409000' }).pluck(:lettering_id).uniq.compact).not_to be_empty
    end

    it 'leaves 100 less to settle on the advance, and nothing left to settle by another invoice' do
      put_doc('BF-I-1', invoice_payload)
      put_doc('BF-I-2', invoice_payload.merge(advance_refs: [ { invoice_ref: 'BF-A-1', amount: '0.01' } ]))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['advance_refs'].first).to match(/exceeds what is left/)
    end

    it 'replays as a no-op, and a change of allocation is a new revision' do
      put_doc('BF-I-1', invoice_payload)
      expect { put_doc('BF-I-1', invoice_payload) }.not_to change(Accounting::Invoice, :count)

      put_doc('BF-I-1', invoice_payload.merge(advance_refs: [ { invoice_ref: 'BF-A-1', amount: '40.00' } ]))

      expect(response).to have_http_status(:ok)
      expect(doc('BF-I-1').map(&:status)).to eq(%w[cancelled partially_paid])
      expect(doc('BF-A-1').first.advance_remaining).to eq(BigDecimal('60'))
      expect(balance('409000')).to eq(BigDecimal('60'))
    end

    it 'gives the advance back when the invoice is cancelled' do
      put_doc('BF-I-1', invoice_payload)

      delete '/api/v1/invoices/BF-I-1', params: { reason: 'Wrong' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok), response.body
      expect(doc('BF-A-1').first.advance_remaining).to eq(100)
      expect(balance('409000')).to eq(100)
    end

    it 'cannot be cancelled while an invoice has settled it' do
      put_doc('BF-I-1', invoice_payload)

      delete '/api/v1/invoices/BF-A-1', params: { reason: 'Wrong' }, headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(doc('BF-A-1').first).to be_posted
    end

    it 'refuses, with 422, an unknown reference, a document that is not an advance, a ceiling overrun' do
      [ [ 'NOPE', '10', /unknown/ ], [ 'BF-A-1', '100.01', /exceeds/ ] ].each do |ref, amount, message|
        put_doc('BF-I-9', invoice_payload.merge(advance_refs: [ { invoice_ref: ref, amount: amount } ]))
        expect(response).to have_http_status(:unprocessable_content)
        expect(json['errors']['advance_refs'].first).to match(message)
      end
      put_doc('BF-I-8', invoice_payload.except(:advance_refs))
      put_doc('BF-I-9', invoice_payload.merge(advance_refs: [ { invoice_ref: 'BF-I-8', amount: '10' } ]))
      expect(json['errors']['advance_refs'].first).to match(/not an advance/)
    end

    it 'refuses a settlement above the total of the invoice' do
      invoice_line.merge!(unit_price: '10.00', vat_rate: '0')

      put_doc('BF-I-1', invoice_payload)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['advance_refs'].first).to match(/more than the invoice/)
    end

    it 'refuses an advance of another supplier or in another currency' do
      create(:partner, :supplier, external_ref: 'BF-P-2')
      put_doc('BF-I-1', invoice_payload.merge(partner_external_ref: 'BF-P-2'))
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['advance_refs'].first).to match(/same supplier/)

      put_doc('BF-I-2', invoice_payload.merge(currency: 'USD', exchange_rate: '1.1'))
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['advance_refs'].first).to match(/same currency/)
    end

    it 'keeps the settlement for the accountant when handed over as a draft, and applies it when she posts' do
      put_doc('BF-I-1', invoice_payload.merge(post: false))

      invoice = doc('BF-I-1').first
      expect(invoice).to be_draft
      expect(invoice.advance_allocations.first.journal_entry).to be_nil
      expect(balance('409000')).to eq(100)
      expect(doc('BF-A-1').first.advance_remaining).to eq(0) # a draft claims its share

      expect(Accounting::PostInvoice.call(invoice: invoice)).to be_success

      expect(invoice.reload).to be_partially_paid
      expect(balance('409000')).to eq(0)
      # the caller learns what the advance paid, in a payment event for an invoice (a document posted in the same request as it is created raises none)
      event = Accounting::InvoiceEvent.where(invoice: invoice, event_type: 'partially_paid').last
      expect(event.payload).to include('document_type' => 'invoice')
      expect(event.payload['settlements'].map { |s| [ s['source'], s['amount'] ] }).to eq([ [ 'advance', '100.0' ] ])
    end
  end
end
