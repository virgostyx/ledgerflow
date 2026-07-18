require 'rails_helper'

RSpec.describe Payments::Actions::BuildSepaXml, type: :service do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account, iban: 'BE68539007547034', bic: 'GKCCBEBB') }
  let(:supplier) { create(:partner, :supplier, name: 'Acme Supplies', iban: 'FR7630006000011234567890189', bic: 'AGRIFRPP') }
  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:invoice) do
    create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year)
  end
  let(:payment_batch) do
    batch = create(:payment_batch, bank_account: bank_account, status: :draft)
    create(:payment_batch_line, payment_batch: batch, invoice: invoice,
           amount: invoice.total_incl_vat, remittance_information: "INV-#{invoice.invoice_number}")
    batch.reload
  end

  it 'builds a valid pain.001 XML document and a message_id' do
    ctx = LightService::Context.make(payment_batch: payment_batch)

    result = described_class.execute(ctx)

    expect(result).to be_success
    expect(result.message_id).to be_present
    expect(result.sepa_xml).to include('CstmrCdtTrfInitn')
    expect(result.sepa_xml).to include(bank_account.iban)
    expect(result.sepa_xml).to include(supplier.iban)
    expect(result.sepa_xml).to include(result.message_id)
  end

  it 'succeeds even when the debtor bank account has no BIC (optional under pain.001.001.03)' do
    bank_account.update_column(:bic, nil)
    ctx = LightService::Context.make(payment_batch: payment_batch)

    result = described_class.execute(ctx)

    expect(result).to be_success
  end
end
