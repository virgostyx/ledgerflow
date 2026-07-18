require 'rails_helper'

RSpec.describe Accounting::PaymentBatchLine, type: :model do
  include_context 'with entity'

  describe 'validations' do
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_numericality_of(:amount).is_greater_than(0) }
    it { is_expected.to belong_to(:payment_batch).class_name('Accounting::PaymentBatch') }
    it { is_expected.to belong_to(:invoice).class_name('Accounting::Invoice') }
  end

  describe 'immutability once the batch is no longer draft' do
    it 'allows updates while the batch is draft' do
      line = create(:payment_batch_line, payment_batch: create(:payment_batch, status: :draft))
      expect { line.update!(remittance_information: 'updated') }.not_to raise_error
    end

    it 'raises on update once the batch has been generated' do
      batch = create(:payment_batch, :generated)
      line  = create(:payment_batch_line, payment_batch: batch)
      expect { line.update!(remittance_information: 'updated') }
        .to raise_error(Accounting::ImmutableRecordError)
    end

    it 'raises on destroy once the batch has been generated' do
      batch = create(:payment_batch, :generated)
      line  = create(:payment_batch_line, payment_batch: batch)
      expect { line.destroy! }.to raise_error(Accounting::ImmutableRecordError)
    end

    it 'allows destroy while the batch is draft' do
      line = create(:payment_batch_line, payment_batch: create(:payment_batch, status: :draft))
      expect { line.destroy! }.not_to raise_error
    end
  end
end
