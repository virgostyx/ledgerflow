require 'rails_helper'

RSpec.describe Accounting::ImportCsvStatement, type: :service do
  include_context 'with entity'

  let(:usd_account) { create(:bank_account).tap { |b| b.update_columns(currency: 'USD') } }

  def import(csv, account = usd_account) = described_class.call(csv: csv, bank_account: account)

  let(:csv) do
    <<~CSV
      date;value_date;amount;reference;description
      30/09/2026;01/10/2026;-1.250,50;WIRE-1;Zambia supplier
      2026-10-02;;2000,00;WIRE-2;Customer receipt
    CSV
  end

  it 'imports signed amounts in the account currency, with European or ISO dates and decimal comma' do
    result = import(csv)

    expect(result).to be_success
    expect(result[:imported_count]).to eq(2)
    out = Accounting::BankTransaction.find_by(reference: 'WIRE-1')
    expect([ out.amount, out.currency, out.transaction_date, out.value_date, out.description ])
      .to eq([ BigDecimal('-1250.50'), 'USD', Date.new(2026, 9, 30), Date.new(2026, 10, 1), 'Zambia supplier' ])
    expect(Accounting::BankTransaction.find_by(reference: 'WIRE-2').amount).to eq(BigDecimal('2000'))
  end

  it 'accepts separate debit and credit columns, and a comma delimiter' do
    result = import("date,debit,credit,description\n2026-10-01,100.00,,Fee\n2026-10-02,,40.00,Refund\n")

    expect(result[:imported_count]).to eq(2)
    expect(Accounting::BankTransaction.pluck(:amount)).to contain_exactly(BigDecimal('-100'), BigDecimal('40'))
  end

  it 'does not import twice: rows without a reference are fingerprinted' do
    csv = "date;amount;description\n2026-10-01;-10,00;Fee\n"
    import(csv)

    expect(import(csv)[:imported_count]).to eq(0)
    expect(Accounting::BankTransaction.count).to eq(1)
  end

  it 'fails and imports nothing when a row is invalid, naming the line' do
    result = import("date;amount;description\n2026-10-01;-10,00;ok\nnot-a-date;5;bad\n")

    expect(result).to be_failure
    expect(result.message).to include('line 3')
    expect(Accounting::BankTransaction.count).to eq(0)
  end

  it 'fails when a currency column differs from the account currency' do
    result = import("date;amount;currency\n2026-10-01;-10;EUR\n")

    expect(result).to be_failure
    expect(result.message).to include('EUR', 'USD')
  end

  it 'fails without the required columns' do
    expect(import("foo;bar\n1;2\n")).to be_failure
  end
end
