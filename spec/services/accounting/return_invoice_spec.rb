require 'rails_helper'

RSpec.describe Accounting::ReturnInvoice, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:purchase) { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'BF-P-1') }
  let(:payload) do
    { external_ref: 'BF-I-1', partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s, post: false,
      lines: [ { account_code: '604000', description: 'X', quantity: '1', unit_price: '100', vat_rate: '21' } ] }
  end
  let(:draft) { Accounting::ExternalInvoice.upsert(payload).invoice }

  it 'cancels the draft and tells the third party, with the reason' do
    result = described_class.call(invoice: draft, reason: 'Wrong budget line')

    expect(result).to be_success
    expect(draft.reload).to be_cancelled
    event = Accounting::InvoiceEvent.where(invoice_id: draft.id).last
    expect(event).to have_attributes(event_type: 'returned')
    expect(event.payload).to include('reason' => 'Wrong budget line', 'external_ref' => 'BF-I-1', 'revision' => 1)
  end

  it 'refuses without a reason and changes nothing' do
    result = described_class.call(invoice: draft, reason: '  ')

    expect(result).to be_failure
    expect(result.message).to match(/reason/i)
    expect(draft.reload).to be_draft
    expect(Accounting::InvoiceEvent.where(invoice_id: draft.id)).to be_empty
  end

  it 'refuses a posted API invoice (it is reversed, not returned)' do
    posted = Accounting::ExternalInvoice.upsert(payload.merge(post: true)).invoice

    result = described_class.call(invoice: posted, reason: 'x')

    expect(result).to be_failure
    expect(posted.reload).to be_posted
  end

  it 'refuses a draft typed in the UI' do
    typed = create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)

    expect(described_class.call(invoice: typed, reason: 'x')).to be_failure
    expect(typed.reload).to be_draft
  end

  it 'lets the third party send a corrected version afterwards (revision 2)' do
    described_class.call(invoice: draft, reason: 'Wrong budget line')

    again = Accounting::ExternalInvoice.upsert(payload.merge(budget_line: '3.2.2'))

    expect(again.status).to eq(:created)
    expect(again.invoice).to have_attributes(revision: 2, status: 'draft')
  end
end
