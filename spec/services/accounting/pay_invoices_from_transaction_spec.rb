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

  describe 'on a foreign account (the bank knows no euro: the EUR amount is the conversion the person confirms)' do
    let!(:misc)     { create(:journal, journal_type: :misc, code: 'OD', label_fr: 'Miscellaneous') }
    let(:usd_bank)  { create(:bank_account).tap { |b| b.update_columns(currency: 'USD') } }

    # 1000 USD and 500 USD booked at 0.9 = 900 and 450 EUR
    def usd_invoice(ref, price)
      Accounting::ExternalInvoice.upsert(
        external_ref: ref, partner_external_ref: 'S1', invoice_type: 'supplier', invoice_date: Date.current.to_s, currency: 'USD', exchange_rate: '1.11111111',
        lines: [ { account_code: '604000', description: 'Work', quantity: '1', unit_price: price, vat_rate: '0' } ]
      ).invoice
    end

    let(:big)   { usd_invoice('U1', '1000') }
    let(:small) { usd_invoice('U2', '500') }
    let(:usd_tx) { create(:bank_transaction, bank_account: usd_bank, amount: BigDecimal('-1500'), currency: 'USD', transaction_date: Date.current, reference: 'USD-GRP') }

    it 'pays them with the EUR amount given, shared between them in proportion, and books the exchange difference' do
      result = call(usd_tx, [ big, small ], eur_amount: BigDecimal('1425'))

      expect(result).to be_success, result.message
      expect([ big, small ].map { |i| i.reload.status }).to all(eq('paid'))
      expect(usd_tx.reload).to be_reconciled
      lines = usd_tx.journal_entry.lines
      expect(lines.where(account: account_440).order(:debit).map { |l| [ l.debit, l.currency, l.amount_currency ] })
        .to eq([ [ BigDecimal('475'), 'USD', BigDecimal('500') ], [ BigDecimal('950'), 'USD', BigDecimal('1000') ] ])
      expect(lines.sum(:credit)).to eq(BigDecimal('1425'))
      fx = Accounting::JournalEntryLine.joins(:account).where(accounting_accounts: { code: '651200' })
      expect(fx.sum(:debit)).to eq(BigDecimal('75')) # 950 - 900 and 475 - 450: paid more than booked
    end

    it 'needs the EUR amount' do
      expect(call(usd_tx, [ big, small ])).to be_failure
    end

    it 'does not take invoices in another currency than the movement' do
      euro = invoice('E1', '1500')

      expect(call(usd_tx, [ big, euro ], eur_amount: BigDecimal('1425'))).to be_failure
    end
  end
end
