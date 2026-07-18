require 'rails_helper'

RSpec.describe Payments::GenerateSepaFile do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }
  let(:supplier)      { create(:partner, :supplier, :with_iban) }
  let(:fiscal_year)   { create(:fiscal_year, status: :open) }
  let(:invoice) do
    create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year)
  end
  let(:payment_batch) do
    batch = create(:payment_batch, bank_account: bank_account, status: :draft)
    create(:payment_batch_line, payment_batch: batch, invoice: invoice, amount: invoice.total_incl_vat)
    batch.reload
  end

  describe '.call' do
    it 'builds and persists the SEPA file, transitioning the batch to generated' do
      result = described_class.call(payment_batch: payment_batch)

      expect(result).to be_success
      batch = result.payment_batch
      expect(batch).to be_generated
      expect(batch.sepa_xml).to include('CstmrCdtTrfInitn')
      expect(batch.message_id).to be_present
      expect(batch.total_amount).to eq(invoice.total_incl_vat)
    end

    it 'refuses to generate a batch that is not draft' do
      payment_batch.update!(status: :cancelled)

      result = described_class.call(payment_batch: payment_batch)

      expect(result).to be_failure
      expect(payment_batch.reload).to be_cancelled
    end
  end
end
