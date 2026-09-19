require 'rails_helper'

RSpec.describe Bank::Simulator::CustomerReceipt, type: :service do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }
  let(:invoice) do
    create(:invoice, :customer, :posted).tap { |i| i.update_columns(total_incl_vat: BigDecimal('1210')) }
  end

  def import(xml)
    Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)
  end

  it 'books a full receipt that the matcher recognises' do
    import(described_class.call(invoice: invoice, bank_account: bank_account))

    tx = Accounting::BankTransaction.sole
    expect(tx.amount).to eq(BigDecimal('1210'))
    expect(Accounting::MatchBankTransaction.call(transaction: tx).target).to eq(invoice)
  end

  it 'supports a partial payment (not matched: amount differs)' do
    import(described_class.call(invoice: invoice, bank_account: bank_account, amount: BigDecimal('500')))

    tx = Accounting::BankTransaction.sole
    expect(tx.amount).to eq(BigDecimal('500'))
    expect(Accounting::MatchBankTransaction.call(transaction: tx)).to be_nil
  end

  it 'supports a transfer without communication (not matched)' do
    import(described_class.call(invoice: invoice, bank_account: bank_account, communication: false))

    expect(Accounting::MatchBankTransaction.call(transaction: Accounting::BankTransaction.sole)).to be_nil
  end

  it 'can be repeated with distinct references (duplicate payment)' do
    2.times { import(described_class.call(invoice: invoice, bank_account: bank_account)) }
    expect(Accounting::BankTransaction.count).to eq(2)
  end
end
