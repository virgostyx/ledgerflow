require 'rails_helper'

RSpec.describe Accounting::MatchBankTransaction, type: :service do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }

  it 'matches a debit to an executed payment batch by message id and amount' do
    batch = create(:payment_batch, :executed, bank_account: bank_account, total_amount: BigDecimal('300'))
    tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-300'), reference: batch.message_id)

    suggestion = described_class.call(transaction: tx)

    expect(suggestion.kind).to eq(:payment_batch)
    expect(suggestion.target).to eq(batch)
    expect(suggestion.confidence).to eq(:high)
  end

  it 'does not match a batch when the amount differs' do
    batch = create(:payment_batch, :executed, bank_account: bank_account, total_amount: BigDecimal('300'))
    tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-299'), reference: batch.message_id)

    expect(described_class.call(transaction: tx)).to be_nil
  end

  it 'does not match a batch that is not executed yet' do
    batch = create(:payment_batch, :generated, bank_account: bank_account, total_amount: BigDecimal('300'))
    tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-300'), reference: batch.message_id)

    expect(described_class.call(transaction: tx)).to be_nil
  end

  context 'customer receipts' do
    let(:invoice) do
      create(:invoice, :customer, :posted).tap { |i| i.update_columns(total_incl_vat: BigDecimal('1210')) }
    end
    let(:comm) { Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(invoice.id)) }

    it 'matches a credit by structured communication and exact amount' do
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1210'), description: "Payment #{comm}")

      suggestion = described_class.call(transaction: tx)

      expect(suggestion.kind).to eq(:invoice)
      expect(suggestion.target).to eq(invoice)
      expect(suggestion.confidence).to eq(:high)
    end

    it 'suggests a partial payment with medium confidence' do
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('500'), description: comm)

      suggestion = described_class.call(transaction: tx)

      expect(suggestion.target).to eq(invoice)
      expect(suggestion.confidence).to eq(:medium)
    end

    it 'suggests an overpayment with medium confidence and the excess' do
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1500'), description: comm)

      suggestion = described_class.call(transaction: tx)

      expect(suggestion.target).to eq(invoice)
      expect(suggestion.confidence).to eq(:medium)
      expect(suggestion.excess).to eq(BigDecimal('290'))
    end

    it 'reports no excess for an exact or partial payment' do
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('500'), description: comm)
      expect(described_class.call(transaction: tx).excess).to eq(0)
    end

    it 'does not match an already paid invoice' do
      invoice.update_columns(status: Accounting::Invoice.statuses[:paid])
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1210'), description: comm)
      expect(described_class.call(transaction: tx)).to be_nil
    end
  end

  it 'returns nil when nothing matches' do
    tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('10'), description: 'random')
    expect(described_class.call(transaction: tx)).to be_nil
  end

  context 'grouped receipts' do
    let!(:fiscal_year) { create(:fiscal_year, status: :open) }
    let(:partner) { create(:partner) }
    let!(:first) do
      create(:invoice, :customer, :posted, partner: partner, fiscal_year: fiscal_year, invoice_number: '2026-0041')
        .tap { |i| i.update_columns(total_incl_vat: BigDecimal('1000')) }
    end
    let!(:second) do
      create(:invoice, :customer, :posted, partner: partner, fiscal_year: fiscal_year, invoice_number: '2026-0043')
        .tap { |i| i.update_columns(total_incl_vat: BigDecimal('500')) }
    end

    def tx(amount: 1500, description: 'Invoices 2026-0041 and 2026-0043')
      create(:bank_transaction, bank_account: bank_account, amount: BigDecimal(amount.to_s), description: description)
    end

    it 'suggests all invoices named in the description when the sum of balances matches' do
      suggestion = described_class.call(transaction: tx)

      expect(suggestion.kind).to eq(:invoices)
      expect(suggestion.target).to contain_exactly(first, second)
      expect(suggestion.confidence).to eq(:medium)
    end

    it 'does not match when the sum differs' do
      expect(described_class.call(transaction: tx(amount: 1400))).to be_nil
    end

    it 'does not match invoices of different partners' do
      second.update_columns(partner_id: create(:partner).id)
      expect(described_class.call(transaction: tx)).to be_nil
    end

    it 'does not match when only one invoice number is present' do
      expect(described_class.call(transaction: tx(amount: 1000, description: 'Invoice 2026-0041'))).to be_nil
    end

    it 'does not confuse a number with a longer one' do
      expect(described_class.call(transaction: tx(description: '2026-00411 and 2026-00431'))).to be_nil
    end
  end
end
