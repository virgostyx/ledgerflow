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

  it 'refuses a draft batch' do
    draft = create(:payment_batch, status: :draft, bank_account: bank_account, total_amount: BigDecimal('300'))
    expect(described_class.call(transaction: tx, payment_batch: draft)).to be_failure
    expect(tx.reload).to be_pending
  end

  context 'with a generated (not yet confirmed) batch' do
    let!(:fiscal_year)     { create(:fiscal_year, status: :open) }
    let!(:payable_account) { create(:account, :supplier, code: '440000') }
    let(:supplier)         { create(:partner, :supplier, :with_iban) }
    let(:invoice) do
      create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year)
    end
    let(:generated) do
      b = create(:payment_batch, :generated, bank_account: bank_account, total_amount: invoice.total_incl_vat)
      create(:payment_batch_line, payment_batch: b, invoice: invoice, amount: invoice.total_incl_vat)
      b.reload
    end
    let(:debit) do
      create(:bank_transaction, bank_account: bank_account, amount: -generated.total_amount, reference: generated.message_id)
    end

    it 'executes the batch, pays the invoices and links the debit to the new settlement entry' do
      result = described_class.call(transaction: debit, payment_batch: generated)

      expect(result).to be_success
      expect(generated.reload).to be_executed
      expect(invoice.reload).to be_paid
      expect(debit.reload).to be_reconciled
      expect(debit.journal_entry).to eq(generated.journal_entry)
    end

    it 'rolls everything back if the batch cannot be executed' do
      invoice.update_column(:status, Accounting::Invoice.statuses[:cancelled])

      expect(described_class.call(transaction: debit, payment_batch: generated)).to be_failure
      expect(generated.reload).to be_generated
      expect(debit.reload).to be_pending
    end
  end

  it 'refuses an amount mismatch' do
    tx.update_columns(amount: BigDecimal('-299'))
    expect(described_class.call(transaction: tx, payment_batch: batch)).to be_failure
  end
end
