require 'rails_helper'

RSpec.describe Accounting::PayInvoiceFromTransaction, type: :service do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'

  let!(:purchase) { create(:journal, :purchase, default_account: account_440) }
  let!(:misc)     { create(:journal, journal_type: :misc, code: 'OD', label_fr: 'Miscellaneous') }
  let!(:supplier) { create(:partner, :supplier, :with_iban, external_ref: 'S1') }
  let(:bank)      { create(:bank_account) }
  let(:usd_bank)  { create(:bank_account).tap { |b| b.update_columns(currency: 'USD') } }

  # 1000 USD booked at 0.9 = 900 EUR
  let(:usd_invoice) do
    Accounting::ExternalInvoice.upsert(
      external_ref: 'USD-1', partner_external_ref: 'S1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
      currency: 'USD', exchange_rate: '0.9',
      lines: [ { account_code: '604000', description: 'Work', quantity: '1', unit_price: '1000', vat_rate: '0' } ]
    ).invoice
  end

  def debit_tx(account, amount, currency)
    create(:bank_transaction, bank_account: account, amount: -BigDecimal(amount), currency: currency,
           transaction_date: Date.current, reference: "PAY-#{amount}")
  end

  def call(**args)
    described_class.call(fiscal_year: fiscal_year, **args)
  end

  it 'pays a foreign invoice from a foreign account and books the exchange difference' do
    tx = debit_tx(usd_bank, '1000', 'USD')

    result = call(transaction: tx, invoice: usd_invoice, eur_amount: BigDecimal('950'))

    expect(result).to be_success, result.message
    expect(usd_invoice.reload).to be_paid
    expect(tx.reload).to be_reconciled
    bank_line = tx.journal_entry.lines.find_by(credit: 950)
    expect([ bank_line.currency, bank_line.amount_currency ]).to eq([ 'USD', BigDecimal('1000') ])
    fx = Accounting::JournalEntryLine.joins(:account).where(accounting_accounts: { code: '651200' })
    expect(fx.sum(:debit)).to eq(BigDecimal('50'))

    settlement = Accounting::InvoiceSettlement.call(usd_invoice.reload)
    expect(settlement.to_payload).to include(amount_eur: '950.0', fx_difference_eur: '-50.0')
    expect(settlement.items.sole).to have_attributes(amount: BigDecimal('1000'), currency: 'USD', amount_eur: BigDecimal('950'))
  end

  it 'pays a foreign invoice from an EUR account with the amount actually debited' do
    tx = debit_tx(bank, '950', 'EUR')

    result = call(transaction: tx, invoice: usd_invoice)

    expect(result).to be_success, result.message
    expect(usd_invoice.reload).to be_paid
  end

  it 'requires the EUR amount when the account is not in EUR' do
    result = call(transaction: debit_tx(usd_bank, '1000', 'USD'), invoice: usd_invoice)

    expect(result).to be_failure
    expect(usd_invoice.reload).to be_posted
  end

  it 'refuses a transaction that is not a pending debit, or an invoice that is not an open supplier invoice' do
    credit = create(:bank_transaction, bank_account: bank, amount: 10, reference: 'IN-1')
    expect(call(transaction: credit, invoice: usd_invoice)).to be_failure

    draft = create(:invoice, :supplier, :draft, :with_lines, partner: supplier, fiscal_year: fiscal_year)
    expect(call(transaction: debit_tx(bank, '5', 'EUR'), invoice: draft)).to be_failure
  end

  it 'refuses a same-currency amount that differs from the invoice total' do
    tx = debit_tx(usd_bank, '999', 'USD')

    result = call(transaction: tx, invoice: usd_invoice, eur_amount: BigDecimal('900'))

    expect(result).to be_failure
    expect(tx.reload).to be_pending
  end
end
