require 'rails_helper'

RSpec.describe Accounting::MatchBankTransaction, type: :service do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }

  it 'matches a debit to an executed payment batch by message id and amount' do
    batch = create(:payment_batch, :executed, bank_account: bank_account, total_amount: BigDecimal('300'))
    tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-300'), reference: batch.message_id)

    suggestion = described_class.call(transaction: tx)

    expect(suggestion.kind).to eq(:payment_batch)
    expect(suggestion.target).to eq(batch)
    expect(suggestion.confidence).to eq(:high)
  end

  it 'does not match a batch when the amount differs' do
    batch = create(:payment_batch, :executed, bank_account: bank_account, total_amount: BigDecimal('300'))
    tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-299'), reference: batch.message_id)

    expect(described_class.call(transaction: tx)).to be_nil
  end

  it 'does not match a batch that is not executed yet' do
    batch = create(:payment_batch, :generated, bank_account: bank_account, total_amount: BigDecimal('300'))
    tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-300'), reference: batch.message_id)

    expect(described_class.call(transaction: tx)).to be_nil
  end

  context 'customer receipts' do
    let(:invoice) do
      create(:invoice, :customer, :posted).tap { |i| i.update_columns(total_incl_vat: BigDecimal('1210')) }
    end
    let(:comm) { Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(invoice.id)) }

    it 'matches a credit by structured communication and exact amount' do
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1210'), description: "Payment #{comm}")

      suggestion = described_class.call(transaction: tx)

      expect(suggestion.kind).to eq(:invoice)
      expect(suggestion.target).to eq(invoice)
      expect(suggestion.confidence).to eq(:high)
    end

    it 'suggests a partial payment with medium confidence' do
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('500'), description: comm)

      suggestion = described_class.call(transaction: tx)

      expect(suggestion.target).to eq(invoice)
      expect(suggestion.confidence).to eq(:medium)
    end

    it 'does not match an overpayment' do
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1500'), description: comm)
      expect(described_class.call(transaction: tx)).to be_nil
    end

    it 'does not match an already paid invoice' do
      invoice.update_columns(status: Accounting::Invoice.statuses[:paid])
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1210'), description: comm)
      expect(described_class.call(transaction: tx)).to be_nil
    end
  end

  it 'returns nil when nothing matches' do
    tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('10'), description: 'random')
    expect(described_class.call(transaction: tx)).to be_nil
  end
end
