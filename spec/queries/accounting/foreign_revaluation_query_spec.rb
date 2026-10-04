require 'rails_helper'

RSpec.describe Accounting::ForeignRevaluationQuery do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'

  let!(:purchase) { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, :with_iban, external_ref: 'S1') }
  let(:as_of)     { Date.current }

  def usd_invoice(ref, price)
    Accounting::ExternalInvoice.upsert(
      external_ref: ref, partner_external_ref: 'S1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
      currency: 'USD', exchange_rate: '1.11111111',
      lines: [ { account_code: '604000', description: 'Work', quantity: '1', unit_price: price, vat_rate: '0' } ]
    ).invoice
  end

  def rows = described_class.new(as_of: as_of).call

  it 'values an open foreign payable at the closing rate: a higher rate is an unrealized loss' do
    usd_invoice('U1', '1000') # 1000 USD booked 900 EUR
    Accounting::ExchangeRate.create!(currency: 'USD', rate_date: as_of, rate: '1.05263158', rate_type: :closing, source: "manual")

    expect(rows.sole).to have_attributes(
      kind: :payable, currency: 'USD', foreign_amount: BigDecimal('1000'), booked_eur: BigDecimal('900'),
      rate: BigDecimal('1.05263158'), revalued_eur: BigDecimal('950'), difference: BigDecimal('-50')
    )
  end

  it 'reports a gain when the rate fell, and ignores a settled invoice' do
    usd_invoice('U1', '1000')
    paid = usd_invoice('U2', '500')
    paid.update_columns(status: Accounting::Invoice.statuses[:paid])
    line = paid.journal_entry.lines.find_by(account: account_440)
    lettering = Accounting::Lettering.create!(account: account_440, code: 'AA', lettered_on: Date.current)
    line.update_columns(lettering_id: lettering.id)
    Accounting::ExchangeRate.create!(currency: 'USD', rate_date: as_of, rate: '1.17647059', rate_type: :closing, source: "manual")

    row = rows.sole
    expect([ row.foreign_amount, row.difference ]).to eq([ BigDecimal('1000'), BigDecimal('50') ])
  end

  it 'has no revalued amount when no rate is known, rather than guessing' do
    usd_invoice('U1', '1000')

    expect(rows.sole).to have_attributes(rate: nil, revalued_eur: nil, difference: nil)
  end

  it 'values the balance of a foreign bank account' do
    usd_account = create(:bank_account).tap { |b| b.update_columns(currency: 'USD') }
    usd_account.journal.default_account.update_columns(code: '550100') if usd_account.journal.default_account
    tx = create(:bank_transaction, bank_account: usd_account, amount: -1000, currency: 'USD', reference: 'F1')
    Accounting::ReconcileBankTransaction.call(transaction: tx, account_id: account_440.id, fiscal_year: fiscal_year, eur_amount: BigDecimal('930'))
    Accounting::ExchangeRate.create!(currency: 'USD', rate_date: as_of, rate: '1.05263158', rate_type: :closing, source: "manual")

    bank = rows.find { |r| r.kind == :bank }
    expect(bank).to have_attributes(foreign_amount: BigDecimal('-1000'), booked_eur: BigDecimal('-930'), revalued_eur: BigDecimal('-950'),
                                    difference: BigDecimal('-20'))
  end

  it 'values an account kept in a foreign currency and flagged for the revaluation, whatever its code' do
    held = create(:account, code: '467000', account_class: 4, account_type: :asset, normal_balance: :debit, currency: 'USD', revalue_at_closing: true)
    income = create(:account, code: '700999', account_class: 7, account_type: :revenue, normal_balance: :credit)
    entry = create(:journal_entry, :draft, journal: purchase, fiscal_year: fiscal_year, entry_date: Date.current)
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: entry, account: held, debit: 930, credit: 0, currency: 'USD', amount_currency: 1000, exchange_rate: BigDecimal('1.07526882'))
    create(:journal_entry_line, journal_entry: entry, account: income, debit: 0, credit: 930)
    Accounting::PostJournalEntry.call!(entry: entry)
    Accounting::ExchangeRate.create!(currency: 'USD', rate_date: as_of, rate: '1.05263158', rate_type: :closing, source: 'manual')

    expect(rows.find { |r| r.kind == :bank }).to have_attributes(foreign_amount: BigDecimal('1000'), booked_eur: BigDecimal('930'), revalued_eur: BigDecimal('950'), difference: BigDecimal('20'))
  end

  it 'says which accounts a position is made of, for the drill-down to the ledger' do
    usd_invoice('U1', '1000')
    expect(rows.sole.account_ids).to eq([ account_440.id ])
  end

  it 'is empty for an entity that only works in EUR' do
    expect(rows).to eq([])
  end
end
