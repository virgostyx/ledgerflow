require 'rails_helper'

RSpec.describe Accounting::ProposeRevaluationEntry, type: :service do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'

  let!(:unrealized) { create(:account, code: '499100', label_fr: 'Unrealized FX losses', account_class: 4, account_type: :liability, normal_balance: :credit) }
  let!(:purchase)   { create(:journal, :purchase, default_account: account_440) }
  let!(:misc)       { create(:journal, journal_type: :misc, code: 'OD', label_fr: 'Miscellaneous') }
  let!(:supplier)   { create(:partner, :supplier, :with_iban, external_ref: 'S1') }
  let(:closing)     { fiscal_year.end_date }

  def usd_payable(ref, price)
    Accounting::ExternalInvoice.upsert(
      external_ref: ref, partner_external_ref: 'S1', invoice_type: 'supplier', invoice_date: fiscal_year.start_date.to_s,
      currency: 'USD', exchange_rate: '0.9',
      lines: [ { account_code: '604000', description: 'Work', quantity: '1', unit_price: price, vat_rate: '0' } ]
    ).invoice
  end

  def rate(value) = Accounting::ExchangeRate.create!(currency: 'USD', rate_date: closing, rate: value)

  def call = described_class.call(fiscal_year: fiscal_year)
  def revaluation_entries = Accounting::JournalEntry.where(source_type: Accounting::JournalEntry::REVALUATION_SOURCE)

  it 'drafts the unrealized loss: Dr 651200 / Cr 499100, dated at the closing date' do
    usd_payable('U1', '1000') # 900 EUR booked
    rate('0.95')

    result = call

    expect(result).to be_success, result.message
    entry = result[:entry]
    expect(entry).to be_draft
    expect(entry.entry_date).to eq(closing)
    expect(entry.lines.find_by(account: account_651200).debit).to eq(BigDecimal('50'))
    expect(entry.lines.find_by(account: unrealized).credit).to eq(BigDecimal('50'))
    expect(result[:reversal]).to be_nil # no next fiscal year yet
  end

  it 'drafts the reversal on the first day of the next fiscal year when it exists' do
    usd_payable('U1', '1000')
    rate('0.95')
    next_year = create(:fiscal_year, status: :pre_closing, entity: entity, year: fiscal_year.year + 1,
                       start_date: closing + 1, end_date: closing + 365)

    result = call

    reversal = result[:reversal]
    expect([ reversal.entry_date, reversal.fiscal_year ]).to eq([ closing + 1, next_year ])
    expect(reversal.lines.find_by(account: unrealized).debit).to eq(BigDecimal('50'))
    expect(reversal.lines.find_by(account: account_651200).credit).to eq(BigDecimal('50'))
  end

  it 'adds the missing reversal later, without a second entry' do
    usd_payable('U1', '1000')
    rate('0.95')
    call
    create(:fiscal_year, status: :pre_closing, entity: entity, year: fiscal_year.year + 1, start_date: closing + 1, end_date: closing + 365)

    expect(call).to be_success
    expect(revaluation_entries.count).to eq(2)
    expect(call[:reversal]).to be_nil
    expect(revaluation_entries.count).to eq(2)
  end

  it 'ignores gains: nothing to book' do
    usd_payable('U1', '1000')
    rate('0.85')

    result = call

    expect(result).to be_failure
    expect(revaluation_entries.count).to eq(0)
  end

  it 'refuses when a closing rate is missing, never guessing' do
    usd_payable('U1', '1000')

    expect(call).to be_failure
    expect(revaluation_entries.count).to eq(0)
  end

  it 'refuses when the unrealized-loss account does not exist' do
    usd_payable('U1', '1000')
    rate('0.95')
    unrealized.destroy!

    result = call

    expect(result).to be_failure
    expect(result.message).to include('499100')
  end
end
