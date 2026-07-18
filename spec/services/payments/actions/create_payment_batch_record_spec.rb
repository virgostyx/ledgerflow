require 'rails_helper'

RSpec.describe Payments::Actions::CreatePaymentBatchRecord, type: :service do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }
  let(:supplier)      { create(:partner, :supplier, :with_iban) }
  let(:fiscal_year)   { create(:fiscal_year, status: :open) }
  let(:invoices) do
    [
      create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year),
      create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year)
    ]
  end

  it 'creates a draft payment batch with one line per invoice' do
    ctx = LightService::Context.make(
      invoices: invoices, bank_account: bank_account, requested_execution_date: Date.current + 1
    )

    result = described_class.execute(ctx)

    expect(result).to be_success
    batch = result.payment_batch
    expect(batch).to be_persisted
    expect(batch).to be_draft
    expect(batch.bank_account).to eq(bank_account)
    expect(batch.lines.count).to eq(2)
    expect(batch.lines.map(&:invoice)).to match_array(invoices)
    expect(batch.lines.map(&:amount)).to all(eq(BigDecimal('1210.00')))
  end

  it 'uses the invoice external_ref as remittance information when present' do
    invoices.first.update!(external_ref: 'STRUCT-REF-001')
    ctx = LightService::Context.make(
      invoices: invoices, bank_account: bank_account, requested_execution_date: Date.current + 1
    )

    result = described_class.execute(ctx)

    line = result.payment_batch.lines.find { |l| l.invoice_id == invoices.first.id }
    expect(line.remittance_information).to eq('STRUCT-REF-001')
  end

  it 'falls back to invoice number and partner name when no external_ref is set' do
    ctx = LightService::Context.make(
      invoices: invoices, bank_account: bank_account, requested_execution_date: Date.current + 1
    )

    result = described_class.execute(ctx)

    line = result.payment_batch.lines.first
    expect(line.remittance_information).to include(line.invoice.invoice_number)
  end
end
