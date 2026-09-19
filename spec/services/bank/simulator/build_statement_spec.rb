require 'rails_helper'

RSpec.describe Bank::Simulator::BuildStatement, type: :service do
  include_context 'with entity'

  let!(:bank_journal) { create(:journal, :bank) }
  let!(:bank_account) { create(:bank_account, journal: bank_journal, iban: 'BE71096123456769') }

  let(:entries) do
    [
      { date: Date.new(2026, 9, 1), amount: BigDecimal('1210.00'), reference: 'E2E-001',
        description: 'Invoice 2026-0042', counterparty_name: 'ABC SA', counterparty_iban: 'BE68539007547034' },
      { date: Date.new(2026, 9, 2), amount: BigDecimal('-500.00'), reference: 'E2E-002',
        description: 'Supplier payment' }
    ]
  end

  def build(list = entries)
    described_class.call(iban: bank_account.iban, entries: list)
  end

  def import(xml)
    Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)
  end

  it 'produces well-formed XML' do
    expect { Nokogiri::XML(build) { |c| c.strict } }.not_to raise_error
  end

  it 'round-trips through ImportCamtStatement' do
    expect(import(build)).to be_success
    credit = Accounting::BankTransaction.find_by(reference: 'E2E-001')
    debit  = Accounting::BankTransaction.find_by(reference: 'E2E-002')

    expect(credit.amount).to eq(BigDecimal('1210.00'))
    expect(credit.transaction_date).to eq(Date.new(2026, 9, 1))
    expect(credit.description).to eq('Invoice 2026-0042')
    expect(debit.amount).to eq(BigDecimal('-500.00'))
  end

  it 'keeps decimal precision' do
    xml = build([
      { date: Date.new(2026, 9, 1), amount: BigDecimal('1250.10'), reference: 'A' },
      { date: Date.new(2026, 9, 1), amount: BigDecimal('99.5'),    reference: 'B' }
    ])
    import(xml)
    expect(Accounting::BankTransaction.find_by(reference: 'A').amount).to eq(BigDecimal('1250.10'))
    expect(Accounting::BankTransaction.find_by(reference: 'B').amount).to eq(BigDecimal('99.50'))
  end

  it 'is idempotent on re-import' do
    xml = build
    import(xml)
    expect(import(xml)[:imported_count]).to eq(0)
  end

  it 'generates distinct references when none is given' do
    xml = build([
      { date: Date.new(2026, 9, 1), amount: BigDecimal('10') },
      { date: Date.new(2026, 9, 1), amount: BigDecimal('10') }
    ])
    expect(import(xml)[:imported_count]).to eq(2)
  end

  it 'rejects a zero amount' do
    expect { build([ { date: Date.new(2026, 9, 1), amount: 0 } ]) }.to raise_error(ArgumentError)
  end
end
