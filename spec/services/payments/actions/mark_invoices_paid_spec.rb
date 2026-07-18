require 'rails_helper'

RSpec.describe Payments::Actions::MarkInvoicesPaid, type: :service do
  include_context 'with entity'

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:supplier)     { create(:partner, :supplier, :with_iban) }
  let(:invoice)      { create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year) }
  let(:payment_batch) do
    batch = create(:payment_batch, :generated)
    create(:payment_batch_line, payment_batch: batch, invoice: invoice, amount: invoice.total_incl_vat)
    batch.reload
  end

  it 'marks every invoice in the batch as paid' do
    ctx = LightService::Context.make(payment_batch: payment_batch)

    result = described_class.execute(ctx)

    expect(result).to be_success
    expect(invoice.reload).to be_paid
  end

  it 'fails when an invoice is not in a payable state' do
    invoice.update_column(:status, Accounting::Invoice.statuses[:draft])
    ctx = LightService::Context.make(payment_batch: payment_batch)

    result = described_class.execute(ctx)

    expect(result).to be_failure
  end
end
