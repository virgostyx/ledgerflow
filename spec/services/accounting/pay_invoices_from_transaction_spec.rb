require 'rails_helper'

# One bank debit that settles several invoices of one supplier (a grouped transfer): each invoice is lettered with its own payment line.
RSpec.describe Accounting::PayInvoicesFromTransaction, type: :service do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'

  let!(:purchase) { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, :with_iban, external_ref: 'S1') }
  let!(:other)    { create(:partner, :supplier, :with_iban, external_ref: 'S2') }
  let(:bank)      { create(:bank_account) }

  def invoice(ref, price, partner: 'S1')
    Accounting::ExternalInvoice.upsert(
      external_ref: ref, partner_external_ref: partner, invoice_type: 'supplier', invoice_date: Date.current.to_s,
      lines: [ { account_code: '604000', description: 'Work', quantity: '1', unit_price: price, vat_rate: '0' } ]
    ).invoice
  end

  let(:first_invoice)  { invoice('A', '100') }
  let(:second_invoice) { invoice('B', '60.50') }

  def debit_tx(amount) = create(:bank_transaction, bank_account: bank, amount: -BigDecimal(amount), currency: 'EUR', transaction_date: Date.current, reference: "GROUP-#{amount}")

  def call(tx, invoices, **args) = described_class.call(transaction: tx, invoices: invoices, fiscal_year: fiscal_year, **args)

  it 'pays all the invoices with one entry: a payable line per invoice, one bank line' do
    tx = debit_tx('160.50')

    result = call(tx, [ first_invoice, second_invoice ])

    expect(result).to be_success, result.message
    expect([ first_invoice, second_invoice ].map { |i| i.reload.status }).to all(eq('paid'))
    expect(tx.reload).to be_reconciled
    lines = tx.journal_entry.lines
    expect(lines.where(account: account_440).pluck(:invoice_id, :debit)).to contain_exactly([ first_invoice.id, BigDecimal('100') ], [ second_invoice.id, BigDecimal('60.50') ])
    expect(lines.sum(:credit)).to eq(BigDecimal('160.50'))
  end

  it 'fails when the invoices do not add up to the movement' do
    result = call(debit_tx('160'), [ first_invoice, second_invoice ])

    expect(result).to be_failure
    expect(first_invoice.reload).to be_posted
  end

  it 'fails when the invoices are not all of one supplier' do
    result = call(debit_tx('160.50'), [ first_invoice, invoice('C', '60.50', partner: 'S2') ])

    expect(result).to be_failure
    expect(result.message).to match(/same supplier/)
  end

  it 'fails for an invoice that is not open, or listed twice' do
    first_invoice.pay!

    expect(call(debit_tx('160.50'), [ first_invoice, second_invoice ])).to be_failure
    expect(call(debit_tx('120'), [ second_invoice, second_invoice ])).to be_failure
  end

  it 'as a draft, books the entry and waits: the invoices are paid when it is validated' do
    tx = debit_tx('160.50')

    result = call(tx, [ first_invoice, second_invoice ], draft: true)

    expect(result).to be_success, result.message
    expect(tx.reload).to be_matched
    expect(first_invoice.reload).to be_posted
  end
end
