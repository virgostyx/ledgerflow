require 'rails_helper'

RSpec.describe Accounting::LinkTransactionToSettlement, type: :service do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }
  let(:batch) { create(:payment_batch, :executed, bank_account: bank_account, total_amount: BigDecimal('300')) }
  let(:tx) { create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-300'), reference: batch.message_id) }

  it 'links the debit to the existing settlement entry without creating a new one' do
    batch
    tx
    result = nil
    expect { result = described_class.call(transaction: tx, payment_batch: batch) }
      .not_to change(Accounting::JournalEntry, :count)

    expect(result).to be_success
    expect(tx.reload).to be_reconciled
    expect(tx.journal_entry).to eq(batch.journal_entry)
  end

  it 'refuses a second transaction for the same batch' do
    described_class.call(transaction: tx, payment_batch: batch)
    other = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-300'), reference: 'other')

    expect(described_class.call(transaction: other, payment_batch: batch)).to be_failure
    expect(other.reload).to be_pending
  end

  it 'refuses an already reconciled transaction' do
    described_class.call(transaction: tx, payment_batch: batch)
    expect(described_class.call(transaction: tx, payment_batch: batch)).to be_failure
  end

  it 'refuses a batch that is not executed' do
    generated = create(:payment_batch, :generated, bank_account: bank_account, total_amount: BigDecimal('300'))
    expect(described_class.call(transaction: tx, payment_batch: generated)).to be_failure
  end

  it 'refuses an amount mismatch' do
    tx.update_columns(amount: BigDecimal('-299'))
    expect(described_class.call(transaction: tx, payment_batch: batch)).to be_failure
  end
end
