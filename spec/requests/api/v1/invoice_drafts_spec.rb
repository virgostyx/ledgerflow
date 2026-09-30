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

  describe 'lines without an account code (the accountant codes them in LedgerFlow)' do
    let(:uncoded) { { description: 'Consulting', quantity: '2', unit_price: '50.00', vat_rate: '21' } }
    let(:suspense) { create(:account, code: '499000', label_fr: "Comptes d'attente", account_class: 4, entity: entity) }

    context 'when the chart has the suspense account' do
      before { suspense }

      it 'puts them on the suspense account 499000' do
        put_invoice(payload.merge(lines: [ uncoded ]))

        expect(response).to have_http_status(:created)
        expect(invoice.lines.map { |l| l.account.code }).to eq(%w[499000])
        expect(invoice.lines.first).to have_attributes(description: 'Consulting', subtotal_excl_vat: BigDecimal('100'))
      end

      it 'mixes coded and uncoded lines, and treats a blank code as absent' do
        put_invoice(payload.merge(lines: [ line, uncoded.merge(account_code: ' ') ]))

        expect(invoice.lines.map { |l| l.account.code }).to eq(%w[604000 499000])
      end

      it 'replays idempotently' do
        put_invoice(payload.merge(lines: [ uncoded ]))
        put_invoice(payload.merge(lines: [ uncoded ]))

        expect(response).to have_http_status(:ok)
        expect(Accounting::Invoice.external.where(external_ref: 'BF-I-1').count).to eq(1)
      end

      it 'still refuses an unknown code' do
        put_invoice(payload.merge(lines: [ uncoded.merge(account_code: '999999') ]))

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it 'answers 422 naming the line when the chart has no suspense account' do
      put_invoice(payload.merge(lines: [ uncoded ]))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['lines[0].account_code'].first).to include('499000')
      expect(Accounting::Invoice.external.count).to eq(0)
    end
  end

  describe 'posting at once with lines still to be coded' do
    let!(:suspense) { create(:account, code: '499000', label_fr: "Comptes d'attente", account_class: 4, entity: entity) }

    it 'answers 422 and writes nothing' do
      uncoded = { description: 'X', quantity: '1', unit_price: '100', vat_rate: '21' }

      expect { put_invoice(payload.merge(post: true, lines: [ uncoded ])) }.not_to change(Accounting::Invoice, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['base'].first).to include('499000')
    end
  end

  describe 'correcting or withdrawing a draft' do
    before { put_invoice }

    def corrected(unit_price: '80.00') = payload.merge(lines: [ line.merge(unit_price: unit_price) ])

    it 'replaces an untouched draft in place: same document, same revision, new content' do
      original_id = invoice.id

      put_invoice(corrected)

      expect(response).to have_http_status(:ok)
      expect(invoice).to have_attributes(id: original_id, revision: 1, status: 'draft', total_incl_vat: BigDecimal('193.6'))
      expect(invoice.lines.count).to eq(1)
      expect(Accounting::Invoice.external.where(external_ref: 'BF-I-1').count).to eq(1)
    end

    it 'replays the corrected content as a no-op' do
      put_invoice(corrected)
      put_invoice(corrected)

      expect(response).to have_http_status(:ok)
      expect(invoice.lines.count).to eq(1)
    end

    it 'answers 409 once the accountant has modified the draft, and leaves it alone' do
      invoice.lines.first.update!(description: 'Recoded by the accountant')

      put_invoice(corrected)

      expect(response).to have_http_status(:conflict)
      expect(json['errors']['base'].first).to match(/accountant/i)
      expect(invoice.lines.first).to have_attributes(description: 'Recoded by the accountant', unit_price: BigDecimal('50'))
    end

    it 'counts an analytical annotation added by the accountant as a modification' do
      axis    = create(:analytical_axis)
      account = create(:analytical_account, analytical_axis: axis)
      create(:invoice_line_annotation, invoice_line: invoice.lines.first, analytical_axis: axis, analytical_account: account)

      put_invoice(corrected)

      expect(response).to have_http_status(:conflict)
    end

    it 'still answers 200 to the very same payload after the accountant touched it (a retry is not a correction)' do
      invoice.lines.first.update!(description: 'Recoded by the accountant')

      put_invoice

      expect(response).to have_http_status(:ok)
    end

    it 'posts the corrected draft when post is switched on' do
      put_invoice(corrected.merge(post: true))

      expect(response).to have_http_status(:ok)
      expect(invoice).to be_posted
      expect(invoice.journal_entry).to be_posted
    end

    it 'cancels a draft on DELETE, with no entry to reverse, and a later PUT starts revision 2' do
      delete '/api/v1/invoices/BF-I-1', params: { reason: 'Sent by mistake' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(invoice).to be_cancelled
      expect(Accounting::JournalEntry.count).to eq(0)

      put_invoice

      expect(response).to have_http_status(:created)
      expect(Accounting::Invoice.external.where(external_ref: 'BF-I-1').order(:revision).map { |i| [ i.revision, i.status ] })
        .to eq([ [ 1, 'cancelled' ], [ 2, 'draft' ] ])
    end
  end

  describe 'an invoice the accountant has already posted' do
    before do
      put_invoice
      Accounting::PostInvoice.call(invoice: invoice) # the accountant posts the draft in LedgerFlow
    end

    it 'cannot be corrected by the third party in draft mode (409): the books belong to the accountant' do
      put_invoice(payload.merge(lines: [ line.merge(unit_price: '80.00') ]))

      expect(response).to have_http_status(:conflict)
      expect(json['errors']['base'].first).to match(/accountant.*cancel/i)
      expect(Accounting::Invoice.external.where(external_ref: 'BF-I-1').count).to eq(1)
      expect(invoice).to have_attributes(status: 'posted', total_incl_vat: BigDecimal('121'))
      expect(Accounting::JournalEntry.where(status: :reversed).count).to eq(0)
    end

    it 'still answers 200 to the very same payload (a retry)' do
      put_invoice

      expect(response).to have_http_status(:ok)
    end

    it 'still accepts a correction from a client that books at once (post absent): revision by reversal, as before' do
      put_invoice(payload.merge(post: nil, lines: [ line.merge(unit_price: '80.00') ]))

      expect(response).to have_http_status(:ok)
      expect(Accounting::Invoice.external.where(external_ref: 'BF-I-1').order(:revision).map(&:status)).to eq(%w[cancelled posted])
    end

    it 'takes a new draft revision once the accountant has cancelled the posted invoice' do
      Accounting::CancelInvoice.call(invoice: invoice)

      put_invoice(payload.merge(lines: [ line.merge(unit_price: '80.00') ]))

      expect(response).to have_http_status(:created)
      expect(json).to include('revision' => 2, 'status' => 'draft')
    end
  end
end
