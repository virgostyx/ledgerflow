require 'rails_helper'

# An API invoice cannot be posted while one of its lines is still on the suspense account (not coded yet).
RSpec.describe Accounting::PostInvoice, 'coding guard', type: :service do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'

  let!(:journal)   { create(:journal, :purchase, default_account: account_440) }
  let!(:suspense)  { create(:account, code: '499000', label_fr: "Comptes d'attente", account_class: 4) }
  let(:supplier)   { create(:partner, :supplier, external_ref: 'BF-P-1') }

  def draft_with(account, digest:)
    invoice = create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year, external_digest: digest)
    create(:invoice_line, invoice: invoice, account: account, description: 'X', quantity: 1, unit_price: 100, vat_rate: 21)
    invoice.reload
  end

  it 'refuses an API invoice with a line on the suspense account, leaving no number and no entry' do
    invoice = draft_with(suspense, digest: 'x')

    result = nil
    expect { result = described_class.call(invoice: invoice) }.not_to change(Accounting::JournalEntry, :count)

    expect(result).to be_failure
    expect(result.message).to include('499000')
    expect(invoice.reload).to have_attributes(status: 'draft', invoice_number: nil)
  end

  it 'posts it once the line is coded' do
    invoice = draft_with(suspense, digest: 'x')
    invoice.lines.first.update!(account: account_604)

    expect(described_class.call(invoice: invoice.reload)).to be_success
    expect(invoice.reload).to be_posted
  end

  it 'leaves invoices typed in the UI alone, even on the suspense account' do
    invoice = draft_with(suspense, digest: nil)

    expect(described_class.call(invoice: invoice)).to be_success
  end
end
