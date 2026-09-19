require 'rails_helper'

RSpec.describe Bank::Simulator::BankFees, type: :service do
  include_context 'with entity'

  let!(:fees_account) { create(:account, code: '651100', label_fr: 'Frais bancaires') }
  let(:bank_account)  { create(:bank_account) }

  def import(xml)
    Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)
  end

  it 'books a small debit with a default amount, which the matcher recognises' do
    import(described_class.call(bank_account: bank_account))

    tx = Accounting::BankTransaction.sole
    expect(tx.amount).to eq(BigDecimal('-4.50'))
    expect(Accounting::MatchBankTransaction.call(transaction: tx)).to have_attributes(kind: :expense, target: fees_account)
  end

  it 'accepts a custom amount and books distinct fees when repeated' do
    2.times { import(described_class.call(bank_account: bank_account, amount: BigDecimal('12.30'))) }

    expect(Accounting::BankTransaction.pluck(:amount)).to all(eq(BigDecimal('-12.30')))
    expect(Accounting::BankTransaction.count).to eq(2)
  end
end
