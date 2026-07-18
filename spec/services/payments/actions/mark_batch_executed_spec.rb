require 'rails_helper'

RSpec.describe Payments::Actions::MarkBatchExecuted, type: :service do
  include_context 'with entity'

  let(:payment_batch)  { create(:payment_batch, :generated) }
  let(:fiscal_year)    { create(:fiscal_year, status: :open) }
  let(:journal_entry)  { create(:journal_entry, fiscal_year: fiscal_year, status: :posted) }

  it 'links the settlement entry, stamps executed_at and transitions to executed' do
    ctx = LightService::Context.make(payment_batch: payment_batch, journal_entry: journal_entry)

    result = described_class.execute(ctx)

    expect(result).to be_success
    payment_batch.reload
    expect(payment_batch).to be_executed
    expect(payment_batch.journal_entry).to eq(journal_entry)
    expect(payment_batch.executed_at).to be_present
  end
end
