require 'rails_helper'

# Paid in cash in a foreign currency: the cash journal holds the currency, the payment is dated on the invoice date at the invoice's own rate (no exchange
# difference), the cash line carries the amount in kwacha and the EUR value, and the settlement tells the third party the amount in the currency paid.
RSpec.describe Accounting::PostInvoice, 'paid from a foreign-currency cash journal', type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:cash_journal)     { create(:journal, :cash, currency: 'ZMW') }
  let(:invoice) do
    create(:invoice, :with_lines, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal, cash_journal: cash_journal,
                                  currency: 'ZMW', exchange_rate: '27.5', exchange_rate_reason: 'contract rate')
  end

  subject(:result) { described_class.call(invoice: invoice) }

  it 'pays the invoice' do
    expect(result).to be_success
    expect(invoice.reload).to be_paid
  end

  it 'books the EUR value of the invoice with the kwacha amount and the rate on both lines' do
    result
    entry  = Accounting::JournalEntry.find_by!(journal: cash_journal)
    total  = invoice.reload.total_incl_vat
    eur    = Fx::Convert.to_eur(total, BigDecimal('27.5'))
    debit  = entry.lines.find_by!(account: account_440)
    credit = entry.lines.find_by!(account: cash_journal.default_account)
    expect([ debit.debit, credit.credit ]).to eq([ eur, eur ])
    expect([ debit.currency, debit.amount_currency, debit.exchange_rate ]).to eq([ 'ZMW', total, BigDecimal('27.5') ])
    expect([ credit.currency, credit.amount_currency, credit.exchange_rate ]).to eq([ 'ZMW', -total, BigDecimal('27.5') ])
  end

  it 'books no exchange difference' do
    expect { result }.not_to change { Accounting::JournalEntry.where('description LIKE ?', 'FX adjustment%').count }
  end

  it 'reports the amount in kwacha and its EUR value in the settlement' do
    result
    item = Accounting::InvoiceSettlement.call(invoice.reload).items.first
    expect([ item.currency, item.amount ]).to eq([ 'ZMW', invoice.total_incl_vat ])
    expect(item.amount_eur).to eq(invoice.total_incl_vat_eur)
  end

  it 'refuses a cash journal of another currency than the invoice' do
    invoice.cash_journal = create(:journal, :cash)
    expect(invoice).not_to be_valid
    expect(invoice.errors[:cash_journal]).to include(a_string_matching(/ZMW/))
  end
end
