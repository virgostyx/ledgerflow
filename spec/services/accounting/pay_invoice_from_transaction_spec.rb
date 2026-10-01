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

  describe 'deposit (partial payment)' do
    let(:eur_invoice) do
      Accounting::ExternalInvoice.upsert(
        external_ref: 'EUR-1', partner_external_ref: 'S1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
        lines: [ { account_code: '604000', description: 'Work', quantity: '1', unit_price: '1000', vat_rate: '0' } ]
      ).invoice
    end

    def fx_sum(side) = Accounting::JournalEntryLine.joins(:account).where(accounting_accounts: { code: '651200' }).sum(side)

    it 'settles part of a foreign invoice, books the exchange difference on the part, then the balance closes it' do
      deposit = debit_tx(usd_bank, '400', 'USD')
      result = call(transaction: deposit, invoice: usd_invoice, eur_amount: BigDecimal('380'), invoice_amount: BigDecimal('400'))

      expect(result).to be_success, result.message
      expect(usd_invoice.reload).to be_partially_paid
      expect(deposit.reload).to be_reconciled
      expect(fx_sum(:debit)).to eq(BigDecimal('20')) # 380 paid for a booked share of 360
      trade = usd_invoice.journal_entry.lines.find_by(account: account_440)
      expect(trade.open_amount).to eq(BigDecimal('540')) # 600 USD left at the booking rate

      balance = debit_tx(usd_bank, '600', 'USD')
      result = call(transaction: balance, invoice: usd_invoice, eur_amount: BigDecimal('560'))

      expect(result).to be_success, result.message
      expect(usd_invoice.reload).to be_paid
      expect(fx_sum(:debit)).to eq(BigDecimal('40'))
      settlement = Accounting::InvoiceSettlement.call(usd_invoice)
      expect(settlement.to_payload).to include(amount_eur: '940.0', fx_difference_eur: '-40.0')
      expect(settlement.items.map(&:amount)).to contain_exactly(BigDecimal('400'), BigDecimal('600'))
    end

    it 'books an exchange gain on a deposit paid for less than its booked share' do
      result = call(transaction: debit_tx(usd_bank, '400', 'USD'), invoice: usd_invoice, eur_amount: BigDecimal('340'), invoice_amount: BigDecimal('400'))

      expect(result).to be_success, result.message
      expect(usd_invoice.reload).to be_partially_paid
      expect(Accounting::InvoiceSettlement.call(usd_invoice).fx_difference_eur).to eq(BigDecimal('20'))
      expect(usd_invoice.journal_entry.lines.find_by(account: account_440).open_amount).to eq(BigDecimal('540'))
    end

    it 'handles an EUR invoice: a deposit leaves it partially paid, the balance settles it' do
      first = call(transaction: debit_tx(bank, '300', 'EUR'), invoice: eur_invoice, invoice_amount: BigDecimal('300'))

      expect(first).to be_success, first.message
      expect(eur_invoice.reload).to be_partially_paid

      second = call(transaction: debit_tx(bank, '700', 'EUR'), invoice: eur_invoice)

      expect(second).to be_success, second.message
      expect(eur_invoice.reload).to be_paid
      expect(Accounting::InvoiceSettlement.call(eur_invoice).amount_eur).to eq(BigDecimal('1000'))
    end

    it 'refuses an amount above what is left, a non-positive one, or a same-currency movement that differs' do
      expect(call(transaction: debit_tx(usd_bank, '1100', 'USD'), invoice: usd_invoice, eur_amount: BigDecimal('990'), invoice_amount: BigDecimal('1100'))).to be_failure
      expect(call(transaction: debit_tx(usd_bank, '5', 'USD'), invoice: usd_invoice, eur_amount: BigDecimal('4'), invoice_amount: BigDecimal('0'))).to be_failure
      expect(call(transaction: debit_tx(usd_bank, '399', 'USD'), invoice: usd_invoice, eur_amount: BigDecimal('380'), invoice_amount: BigDecimal('400'))).to be_failure
      expect(usd_invoice.reload).to be_posted
    end
  end
end
