require 'rails_helper'

RSpec.describe Bank::Simulator::PayBatch, type: :service do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }
  let(:batch) do
    b = create(:payment_batch, :generated, bank_account: bank_account,
               requested_execution_date: Date.new(2026, 9, 10))
    b.update_columns(total_amount: BigDecimal('1210.50'))
    b
  end

  def import(xml)
    Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)
  end

  it 'books one grouped debit for the whole batch, referenced by its message id' do
    expect(import(described_class.call(payment_batch: batch))).to be_success

    tx = Accounting::BankTransaction.sole
    expect(tx.amount).to eq(BigDecimal('-1210.50'))
    expect(tx.reference).to eq(batch.message_id)
    expect(tx.transaction_date).to eq(Date.new(2026, 9, 10))
  end

  it 'refuses a batch that was never generated' do
    draft = create(:payment_batch, status: :draft, bank_account: bank_account)
    expect { described_class.call(payment_batch: draft) }.to raise_error(ArgumentError)
  end
end
