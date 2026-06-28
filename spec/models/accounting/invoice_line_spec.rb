require 'rails_helper'

RSpec.describe Accounting::InvoiceLine, type: :model do
  include_context 'with entity'

  describe 'associations' do
    it { should belong_to(:invoice).class_name('Accounting::Invoice') }
    it { should belong_to(:account).class_name('Accounting::Account') }
  end

  describe 'validations' do
    subject { build(:invoice_line) }

    it { should validate_presence_of(:description) }
    it { should validate_numericality_of(:quantity).is_greater_than(0) }
    it { should validate_numericality_of(:unit_price).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:vat_rate).is_greater_than_or_equal_to(0) }
  end

  describe 'MonetaryPrecision' do
    let(:line) { build(:invoice_line, unit_price: 100.0, vat_rate: 21.0) }

    it 'convertit unit_price en BigDecimal' do
      expect(line.unit_price).to be_a(BigDecimal)
    end

    it 'convertit vat_rate en BigDecimal' do
      expect(line.vat_rate).to be_a(BigDecimal)
    end
  end

  describe '#compute_amounts' do
    let(:line) { build(:invoice_line, quantity: '3', unit_price: '100.00', vat_rate: '21.00') }

    before { line.compute_amounts }

    it 'calcule subtotal_excl_vat = quantity * unit_price' do
      expect(line.subtotal_excl_vat).to eq(BigDecimal('300.00'))
    end

    it 'calcule vat_amount = subtotal * vat_rate / 100' do
      expect(line.vat_amount).to eq(BigDecimal('63.00'))
    end

    it 'calcule total_incl_vat = subtotal + vat' do
      expect(line.total_incl_vat).to eq(BigDecimal('363.00'))
    end
  end

  describe 'callbacks' do
    let(:account) { create(:account) }
    let(:invoice) { create(:invoice) }

    it 'compute_amounts est appelé avant validation' do
      line = build(:invoice_line, invoice: invoice, account: account,
                   quantity: '2', unit_price: '50.00', vat_rate: '0.00')
      line.valid?
      expect(line.subtotal_excl_vat).to eq(BigDecimal('100.00'))
    end

    it 'compute_amounts ne plante pas si unit_price est nil' do
      line = build(:invoice_line, invoice: invoice, account: account, unit_price: nil)
      expect { line.valid? }.not_to raise_error
    end
  end

  describe 'vat_rate 0%' do
    let(:line) { build(:invoice_line, quantity: '5', unit_price: '20.00', vat_rate: '0.00') }

    before { line.compute_amounts }

    it 'vat_amount est nul' do
      expect(line.vat_amount).to eq(BigDecimal('0'))
    end

    it 'total_incl_vat égale subtotal_excl_vat' do
      expect(line.total_incl_vat).to eq(line.subtotal_excl_vat)
    end
  end
end
