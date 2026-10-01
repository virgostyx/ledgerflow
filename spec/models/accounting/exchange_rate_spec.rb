require 'rails_helper'

RSpec.describe Accounting::ExchangeRate, type: :model do
  include_context 'with entity'

  def rate(currency, date, value) = described_class.create!(currency: currency, rate_date: date, rate: value)

  describe 'validations' do
    it 'requires an ISO currency other than EUR, a positive rate and a date' do
      expect(described_class.new(currency: 'USD', rate_date: Date.current, rate: '0.9')).to be_valid
      expect(described_class.new(currency: 'EUR', rate_date: Date.current, rate: '1')).not_to be_valid
      expect(described_class.new(currency: 'US', rate_date: Date.current, rate: '1')).not_to be_valid
      expect(described_class.new(currency: 'USD', rate_date: Date.current, rate: '0')).not_to be_valid
      expect(described_class.new(currency: 'USD', rate: '0.9')).not_to be_valid
    end

    it 'is unique per currency and day' do
      rate('USD', Date.new(2026, 9, 30), '0.9')
      expect(described_class.new(currency: 'USD', rate_date: Date.new(2026, 9, 30), rate: '0.8')).not_to be_valid
    end
  end

  describe '.rate_for' do
    before do
      rate('USD', Date.new(2026, 9, 1), '0.90')
      rate('USD', Date.new(2026, 9, 30), '0.95')
    end

    it 'returns the latest rate on or before the date' do
      expect(described_class.rate_for('USD', Date.new(2026, 9, 15))).to eq(BigDecimal('0.90'))
      expect(described_class.rate_for('usd', Date.new(2026, 9, 30))).to eq(BigDecimal('0.95'))
    end

    it 'is 1 for EUR, nil when no rate is known yet' do
      expect(described_class.rate_for('EUR', Date.current)).to eq(1)
      expect(described_class.rate_for('USD', Date.new(2026, 8, 1))).to be_nil
      expect(described_class.rate_for('JPY', Date.current)).to be_nil
    end
  end
end
