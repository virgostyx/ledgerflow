require 'rails_helper'

RSpec.describe Accounting::PaymentBatch, type: :model do
  include_context 'with entity'

  describe 'validations' do
    it { is_expected.to validate_presence_of(:requested_execution_date) }
    it { is_expected.to belong_to(:bank_account).class_name('Accounting::BankAccount') }
    it { is_expected.to belong_to(:journal_entry).class_name('Accounting::JournalEntry').optional }
  end

  describe 'associations' do
    it do
      is_expected.to have_many(:lines)
        .class_name('Accounting::PaymentBatchLine')
        .with_foreign_key(:payment_batch_id)
        .dependent(:destroy)
    end
  end

  describe 'enums' do
    it do
      is_expected.to define_enum_for(:status)
        .with_values(draft: 0, generated: 1, executed: 2, cancelled: 3)
        .backed_by_column_of_type(:integer)
    end
  end

  describe 'AASM transitions' do
    it 'starts as draft' do
      expect(build(:payment_batch)).to be_draft
    end

    it 'transitions from draft to generated' do
      batch = create(:payment_batch, status: :draft)
      batch.generate!
      expect(batch).to be_generated
    end

    it 'transitions from generated to executed' do
      batch = create(:payment_batch, :generated)
      batch.execute!
      expect(batch).to be_executed
    end

    it 'cannot execute a draft batch' do
      batch = create(:payment_batch, status: :draft)
      expect { batch.execute! }.to raise_error(AASM::InvalidTransition)
    end

    it 'transitions from draft to cancelled' do
      batch = create(:payment_batch, status: :draft)
      batch.cancel!
      expect(batch).to be_cancelled
    end

    it 'transitions from generated to cancelled' do
      batch = create(:payment_batch, :generated)
      batch.cancel!
      expect(batch).to be_cancelled
    end

    it 'cannot cancel an executed batch' do
      batch = create(:payment_batch, :executed)
      expect { batch.cancel! }.to raise_error(AASM::InvalidTransition)
    end
  end

  describe '#destroyable?' do
    it 'is destroyable while draft' do
      expect(create(:payment_batch, status: :draft)).to be_destroyable
    end

    it 'is not destroyable once generated' do
      expect(create(:payment_batch, :generated)).not_to be_destroyable
    end
  end

  describe 'destroy guard' do
    it 'raises when destroying a non-draft batch' do
      batch = create(:payment_batch, :generated)
      expect { batch.destroy! }.to raise_error(Accounting::ImmutableRecordError)
    end

    it 'allows destroying a draft batch' do
      batch = create(:payment_batch, status: :draft)
      expect { batch.destroy! }.not_to raise_error
    end
  end
end
