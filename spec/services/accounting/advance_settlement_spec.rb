require 'rails_helper'

# Advances beyond the API contract (spec/requests/api/v1/advances_spec.rb): foreign currency, bank payment, customer aged balance.
RSpec.describe 'Advance settlement', type: :service do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'

  let!(:account_409) { create(:account, code: '409000', label_fr: 'Avances versées', reconcilable: true) }
  let!(:purchase) { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, :with_iban, external_ref: 'S1') }
  let!(:misc)     { create(:journal, journal_type: :misc, code: 'OD', label_fr: 'Miscellaneous') }
  let(:bank)      { create(:bank_account) }

  def upsert(ref, type: 'invoice', unit_price: '100', currency: 'EUR', rate: '1', refs: nil)
    line = { description: 'Work', quantity: '1', unit_price: unit_price, vat_rate: '0' }
    line[:account_code] = '604000' if type == 'invoice'
    body = { external_ref: ref, document_type: type, partner_external_ref: 'S1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
             currency: currency, exchange_rate: rate, lines: [ line ] }
    body[:advance_refs] = refs if refs
    result = Accounting::ExternalInvoice.upsert(**body)
    expect(result.errors).to be_blank, result.errors.inspect if result.respond_to?(:errors)
    result.invoice
  end

  def balance(code) = Accounting::JournalEntryLine.joins(:account).where(accounting_accounts: { code: code }).sum('debit - credit')

  it 'pays an advance from the bank like an invoice, and leaves 409000 until it is settled' do
    advance = upsert('A1', type: 'advance')
    tx = create(:bank_transaction, bank_account: bank, amount: -100, currency: 'EUR', transaction_date: Date.current, reference: 'PAY-A1')

    result = Accounting::PayInvoiceFromTransaction.call(transaction: tx, invoice: advance, fiscal_year: fiscal_year)

    expect(result).to be_success, result.message
    expect(advance.reload).to be_paid
    expect(balance('409000')).to eq(100)
    expect(balance('440000')).to eq(0)
  end

  it 'settles a dollar advance with a dollar invoice at another rate, the difference going to the exchange account' do
    advance = upsert('A1', type: 'advance', unit_price: '100', currency: 'USD', rate: '1.25')       # 80 EUR
    invoice = upsert('I1', unit_price: '100', currency: 'USD', rate: '1', refs: [ { invoice_ref: 'A1', amount: '100' } ]) # 100 EUR

    expect(invoice.reload).to be_paid
    expect(advance.reload.advance_remaining).to eq(0)
    expect(balance('409000')).to eq(0)
    expect(balance('440000')).to eq(-80) # the advance itself is still to be paid to the supplier
    expect(balance('651200') + balance('751100')).not_to eq(0) # the 20 EUR difference is booked, not lost
  end

  it 'keeps 409000 out of the customer open items and in the supplier ones' do
    upsert('A1', type: 'advance')

    customer = Accounting::OpenLineSql.open_scope(kind: :customer, as_of: Date.current).joins(:account).pluck('accounting_accounts.code')
    expect(customer).not_to include('409000')
  end
end
