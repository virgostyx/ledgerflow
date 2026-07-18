require 'rails_helper'

RSpec.describe Payments::Actions::PersistGeneratedFile, type: :service do
  include_context 'with entity'

  let(:supplier)     { create(:partner, :supplier, :with_iban) }
  let(:fiscal_year)  { create(:fiscal_year, status: :open) }
  let(:invoice)      { create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year) }
  let(:payment_batch) do
    batch = create(:payment_batch, status: :draft)
    create(:payment_batch_line, payment_batch: batch, invoice: invoice, amount: BigDecimal('1210.00'))
    batch.reload
  end

  it 'persists the generated file and transitions the batch to generated' do
    ctx = LightService::Context.make(
      payment_batch: payment_batch, sepa_xml: '<Document/>', message_id: 'abc123'
    )

    result = described_class.execute(ctx)

    expect(result).to be_success
    payment_batch.reload
    expect(payment_batch).to be_generated
    expect(payment_batch.sepa_xml).to eq('<Document/>')
    expect(payment_batch.message_id).to eq('abc123')
    expect(payment_batch.total_amount).to eq(BigDecimal('1210.00'))
    expect(payment_batch.generated_at).to be_present
  end
end
