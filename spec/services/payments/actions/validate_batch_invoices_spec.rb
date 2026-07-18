require 'rails_helper'

RSpec.describe Payments::Actions::ValidateBatchInvoices, type: :service do
  include_context 'with entity'

  let(:supplier) { create(:partner, :supplier, :with_iban) }

  def posted_supplier_invoice(partner: supplier)
    create(:invoice, :supplier, :posted, :with_lines, partner: partner)
  end

  it 'passes with a list of eligible posted supplier invoices' do
    invoice = posted_supplier_invoice
    ctx = LightService::Context.make(invoice_ids: [ invoice.id ])

    result = described_class.execute(ctx)

    expect(result).to be_success
    expect(result.invoices).to contain_exactly(invoice)
  end

  it 'fails when no invoice_ids are given' do
    ctx = LightService::Context.make(invoice_ids: [])

    result = described_class.execute(ctx)

    expect(result).to be_failure
  end

  it 'fails when an invoice is not posted' do
    invoice = create(:invoice, :supplier, :draft, :with_lines, partner: supplier)
    ctx = LightService::Context.make(invoice_ids: [ invoice.id ])

    result = described_class.execute(ctx)

    expect(result).to be_failure
  end

  it 'fails when an invoice is a customer invoice' do
    invoice = create(:invoice, :customer, :posted, :with_lines, partner: create(:partner, :with_iban))
    ctx = LightService::Context.make(invoice_ids: [ invoice.id ])

    result = described_class.execute(ctx)

    expect(result).to be_failure
  end

  it 'fails when the partner has no IBAN' do
    partner_without_iban = create(:partner, :supplier)
    invoice = posted_supplier_invoice(partner: partner_without_iban)
    ctx = LightService::Context.make(invoice_ids: [ invoice.id ])

    result = described_class.execute(ctx)

    expect(result).to be_failure
  end

  it 'fails when the invoice already belongs to an active payment batch' do
    invoice = posted_supplier_invoice
    create(:payment_batch_line, invoice: invoice, payment_batch: create(:payment_batch, status: :draft))
    ctx = LightService::Context.make(invoice_ids: [ invoice.id ])

    result = described_class.execute(ctx)

    expect(result).to be_failure
  end

  it 'succeeds when the invoice only belongs to a cancelled batch' do
    invoice = posted_supplier_invoice
    create(:payment_batch_line, invoice: invoice, payment_batch: create(:payment_batch, :cancelled))
    ctx = LightService::Context.make(invoice_ids: [ invoice.id ])

    result = described_class.execute(ctx)

    expect(result).to be_success
  end
end
