require 'rails_helper'

RSpec.describe Payments::CreateDraftBatch do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }
  let(:supplier)      { create(:partner, :supplier, :with_iban) }
  let(:fiscal_year)   { create(:fiscal_year, status: :open) }
  let(:invoice) do
    create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year)
  end

  describe '.call' do
    it 'creates a draft payment batch from eligible invoices' do
      result = described_class.call(
        invoice_ids: [ invoice.id ], bank_account: bank_account, requested_execution_date: Date.current + 1
      )

      expect(result).to be_success
      batch = result.payment_batch
      expect(batch).to be_draft
      expect(batch.lines.sole.invoice).to eq(invoice)
    end

    it 'rolls back and fails when an invoice is not eligible' do
      draft_invoice = create(:invoice, :supplier, :draft, :with_lines, partner: supplier, fiscal_year: fiscal_year)

      result = described_class.call(
        invoice_ids: [ draft_invoice.id ], bank_account: bank_account, requested_execution_date: Date.current + 1
      )

      expect(result).to be_failure
      expect(Accounting::PaymentBatch.count).to eq(0)
    end

    it 'does not persist a batch when no invoices are given' do
      result = described_class.call(
        invoice_ids: [], bank_account: bank_account, requested_execution_date: Date.current + 1
      )

      expect(result).to be_failure
      expect(Accounting::PaymentBatch.count).to eq(0)
    end
  end
end
