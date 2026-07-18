require 'rails_helper'

RSpec.describe Payments::ExecutePaymentBatch do
  include_context 'with entity'

  let!(:fiscal_year)     { create(:fiscal_year, status: :open) }
  let!(:payable_account) { create(:account, :supplier, code: '440000') }
  let(:bank_account)      { create(:bank_account) }
  let(:supplier)           { create(:partner, :supplier, :with_iban) }
  let(:invoice) do
    create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year)
  end
  let(:payment_batch) do
    batch = create(:payment_batch, :generated, bank_account: bank_account)
    create(:payment_batch_line, payment_batch: batch, invoice: invoice, amount: invoice.total_incl_vat)
    batch.reload
  end

  describe '.call' do
    it 'posts the settlement entry, marks invoices paid and executes the batch' do
      result = described_class.call(payment_batch: payment_batch)

      expect(result).to be_success
      payment_batch.reload
      expect(payment_batch).to be_executed
      expect(payment_batch.journal_entry).to be_posted
      expect(invoice.reload).to be_paid
    end

    it 'refuses to execute a batch that has not been generated yet' do
      draft_batch = create(:payment_batch, status: :draft, bank_account: bank_account)

      result = described_class.call(payment_batch: draft_batch)

      expect(result).to be_failure
      expect(draft_batch.reload).to be_draft
    end

    it 'rolls back everything if marking an invoice paid fails' do
      invoice.update_column(:status, Accounting::Invoice.statuses[:cancelled])

      result = described_class.call(payment_batch: payment_batch)

      expect(result).to be_failure
      expect(payment_batch.reload).to be_generated
      expect(Accounting::JournalEntry.where(source_type: 'Accounting::PaymentBatch')).to be_empty
    end
  end
end
