require 'rails_helper'

RSpec.describe Payments::Actions::CreateSettlementJournalEntry, type: :service do
  include_context 'with entity'

  let!(:fiscal_year)   { create(:fiscal_year, status: :open) }
  let!(:payable_account) { create(:account, :supplier, code: '440000') }
  let(:bank_account)   { create(:bank_account) }
  let(:supplier)        { create(:partner, :supplier, :with_iban) }
  let(:invoice) do
    create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year)
  end
  let(:payment_batch) do
    batch = create(:payment_batch, :generated, bank_account: bank_account)
    create(:payment_batch_line, payment_batch: batch, invoice: invoice, amount: invoice.total_incl_vat)
    batch.reload
  end

  it 'creates a posted, balanced journal entry debiting 440000 and crediting the bank account' do
    ctx = LightService::Context.make(payment_batch: payment_batch)

    result = described_class.execute(ctx)

    expect(result).to be_success
    entry = result.journal_entry
    expect(entry).to be_posted
    expect(entry.journal).to eq(bank_account.journal)
    expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))

    debit_line = entry.lines.find { |l| l.debit.positive? }
    expect(debit_line.account).to eq(payable_account)
    expect(debit_line.partner).to eq(supplier)
    expect(debit_line.debit).to eq(invoice.total_incl_vat)

    credit_line = entry.lines.find { |l| l.credit.positive? }
    expect(credit_line.account).to eq(bank_account.journal.default_account)
    expect(credit_line.credit).to eq(invoice.total_incl_vat)
  end

  it 'fails when there is no open fiscal year' do
    fiscal_year.update!(status: :closed)
    ctx = LightService::Context.make(payment_batch: payment_batch)

    result = described_class.execute(ctx)

    expect(result).to be_failure
  end
end
