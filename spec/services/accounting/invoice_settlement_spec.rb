require 'rails_helper'

# What an auditor needs about a supplier payment: value date, bank reference, the amount really paid for this invoice.
RSpec.describe Accounting::InvoiceSettlement, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:purchase)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier)  { create(:partner, :supplier, external_ref: 'BF-P-1') }
  let(:bank_account) { create(:bank_account) }

  def api_invoice(ref, unit_price: '100')
    Accounting::ExternalInvoice.upsert(
      external_ref: ref, partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
      lines: [ { account_code: '604000', description: 'X', quantity: '1', unit_price: unit_price, vat_rate: '21' } ]
    ).invoice
  end

  def trade_line(invoice) = invoice.journal_entry.lines.find_by(account: account_440)

  # A bank debit booked on the payable account by the regular reconciliation (the accountant letters it afterwards).
  def reconciled_debit(amount, transaction_date:, value_date:, reference:)
    tx = create(:bank_transaction, bank_account: bank_account, amount: -BigDecimal(amount.to_s), transaction_date: transaction_date,
                                   value_date: value_date, reference: reference, description: 'Payment ACME')
    Accounting::ReconcileBankTransaction.call(transaction: tx, account_id: account_440.id, fiscal_year: fiscal_year)
    tx.reload
    debit = tx.journal_entry.lines.find_by(account: account_440)
    debit.update_columns(partner_id: supplier.id) # the accountant attaches the supplier: lettering needs the same partner
    [ tx, debit.reload ]
  end

  it 'gives the value date, reference and amount of the bank debit that settled a lettered invoice' do
    invoice = api_invoice('BF-I-1')
    tx, debit = reconciled_debit(121, transaction_date: 3.days.ago.to_date, value_date: 2.days.ago.to_date, reference: 'E2E-REF-1')
    Accounting::LetterLines.call(lines: [ trade_line(invoice), debit ])

    settlement = described_class.call(invoice.reload)

    expect(settlement).to have_attributes(amount_eur: BigDecimal('121'), paid_on: 2.days.ago.to_date, reference: 'E2E-REF-1')
    expect(settlement.items.size).to eq(1)
    expect(settlement.items.first).to have_attributes(value_date: 2.days.ago.to_date, transaction_date: 3.days.ago.to_date,
                                                      reference: 'E2E-REF-1', description: 'Payment ACME', amount: BigDecimal('121'),
                                                      currency: 'EUR', amount_eur: BigDecimal('121'), shared: false, source: 'bank_transaction')
  end

  it 'reports a partial payment with what is settled so far' do
    invoice = api_invoice('BF-I-1')
    _tx, debit = reconciled_debit(60, transaction_date: Date.current, value_date: Date.current, reference: 'E2E-PART')
    Accounting::AllocateLines.call(lines: [ trade_line(invoice), debit ])

    settlement = described_class.call(invoice.reload)

    expect(settlement).to have_attributes(amount_eur: BigDecimal('60'), reference: 'E2E-PART')
    expect(invoice).to be_partially_paid
  end

  it 'gives each invoice its own share of a transfer that pays two of them, flagged shared' do
    first  = api_invoice('BF-I-1', unit_price: '50')  # 60.50
    second = api_invoice('BF-I-2', unit_price: '50')
    _tx, debit = reconciled_debit(121, transaction_date: Date.current, value_date: Date.current, reference: 'E2E-BOTH')
    Accounting::AllocateLines.call(lines: [ trade_line(first), debit ])
    Accounting::AllocateLines.call(lines: [ trade_line(second), debit.reload ])

    a = described_class.call(first.reload)
    b = described_class.call(second.reload)

    expect([ a.amount_eur, b.amount_eur ]).to eq([ BigDecimal('60.5'), BigDecimal('60.5') ])
    expect(a.items.first).to have_attributes(amount: BigDecimal('121'), shared: true, reference: 'E2E-BOTH')
  end

  describe 'a SEPA payment batch' do
    let(:invoice) { api_invoice('BF-I-1') }
    let(:batch) do
      b = create(:payment_batch, :generated, bank_account: bank_account, requested_execution_date: 1.day.from_now.to_date, total_amount: BigDecimal('121'))
      create(:payment_batch_line, payment_batch: b, invoice: invoice, amount: invoice.total_incl_vat)
      b.reload
    end

    it 'falls back to the batch until the bank confirms: batch reference, no bank value date yet' do
      Payments::ExecutePaymentBatch.call(payment_batch: batch)

      settlement = described_class.call(invoice.reload)

      expect(settlement.items.first).to have_attributes(source: 'payment_batch', reference: batch.message_id, amount_eur: BigDecimal('121'))
    end

    it 'then takes the value date and the reference of the bank debit once it is linked to the batch' do
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-121'), transaction_date: Date.current,
                                     value_date: 1.day.from_now.to_date, reference: 'BANK-REF-9')
      Accounting::LinkTransactionToSettlement.call(transaction: tx, payment_batch: batch)

      settlement = described_class.call(invoice.reload)

      expect(settlement).to have_attributes(amount_eur: BigDecimal('121'), paid_on: 1.day.from_now.to_date, reference: 'BANK-REF-9')
      expect(settlement.items.first.source).to eq('bank_transaction')
    end
  end

  it 'falls back to the lettered counterpart entry when no bank transaction is involved (manual entry)' do
    invoice = api_invoice('BF-I-1')
    od = create(:journal, :cash)
    entry = create(:journal_entry, status: :posted, journal: od, fiscal_year: fiscal_year, entry_date: 5.days.ago.to_date, reference: 'OD-77')
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    debit = create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, debit: BigDecimal('121'), credit: 0)
    Accounting::LetterLines.call(lines: [ trade_line(invoice), debit ])

    settlement = described_class.call(invoice.reload)

    expect(settlement.items.first).to have_attributes(source: 'journal_entry', reference: 'OD-77', value_date: 5.days.ago.to_date,
                                                      amount_eur: BigDecimal('121'))
  end

  it 'falls back to the whole invoice today when nothing else is known' do
    invoice = api_invoice('BF-I-1')
    invoice.pay!

    settlement = described_class.call(invoice.reload)

    expect(settlement).to have_attributes(amount_eur: BigDecimal('121'), paid_on: Date.current)
    expect(settlement.items.first.source).to eq('transition')
  end

  describe 'foreign-currency invoice' do
    let!(:misc) { create(:journal, journal_type: :misc, code: 'OD', label_fr: 'Miscellaneous') }

    def usd_invoice
      Accounting::ExternalInvoice.upsert(
        external_ref: 'USD-1', partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
        currency: 'USD', exchange_rate: '0.9',
        lines: [ { account_code: '604000', description: 'X', quantity: '1', unit_price: '1000', vat_rate: '0' } ]
      ).invoice # booked 900 EUR
    end

    it 'reports the EUR really paid and the exchange loss when more was debited than booked' do
      invoice = usd_invoice
      _tx, debit = reconciled_debit(950, transaction_date: Date.current, value_date: Date.current, reference: 'EUR-950')
      Accounting::LetterLines.call(lines: [ trade_line(invoice), debit ])

      settlement = described_class.call(invoice.reload)

      expect(settlement.amount_eur).to eq(BigDecimal('950'))
      expect(settlement.fx_difference_eur).to eq(BigDecimal('-50'))
      expect(settlement.to_payload[:fx_difference_eur]).to eq('-50.0')
    end

    it 'reports an exchange gain when less was debited than booked, without counting the adjustment as a payment' do
      invoice = usd_invoice
      _tx, debit = reconciled_debit(850, transaction_date: Date.current, value_date: Date.current, reference: 'EUR-850')
      Accounting::LetterLines.call(lines: [ trade_line(invoice), debit ])

      settlement = described_class.call(invoice.reload)

      expect(settlement.amount_eur).to eq(BigDecimal('850'))
      expect(settlement.fx_difference_eur).to eq(BigDecimal('50'))
      expect(settlement.items.size).to eq(1)
    end

    it 'is zero for an EUR invoice' do
      invoice = api_invoice('BF-I-EUR')
      _tx, debit = reconciled_debit(121, transaction_date: Date.current, value_date: Date.current, reference: 'E')
      Accounting::LetterLines.call(lines: [ trade_line(invoice), debit ])

      expect(described_class.call(invoice.reload).fx_difference_eur).to eq(0)
    end
  end
end
