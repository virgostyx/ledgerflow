require 'rails_helper'

RSpec.describe Accounting::PaymentBatchPresenter, type: :presenter do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }
  let(:payment_batch) do
    create(:payment_batch, bank_account: bank_account, requested_execution_date: Date.new(2026, 7, 20),
           total_amount: BigDecimal('1210.00'))
  end
  let(:presenter) { described_class.new(payment_batch) }

  describe '#formatted_total' do
    it 'formats the total amount as currency' do
      expect(presenter.formatted_total).to include('1 210,00')
    end
  end

  describe '#formatted_requested_execution_date' do
    it 'formats the requested execution date' do
      expect(presenter.formatted_requested_execution_date).to eq('20/07/2026')
    end
  end

  describe '#status_label' do
    it 'returns the humanized status' do
      expect(presenter.status_label).to eq('Draft')
    end
  end

  describe '#status_badge_variant' do
    it 'returns the badge variant for the status' do
      expect(presenter.status_badge_variant).to eq(:default)
    end
  end

  describe '#line_count' do
    it 'returns the number of lines' do
      create(:payment_batch_line, payment_batch: payment_batch)
      expect(presenter.line_count).to eq(1)
    end
  end
end
