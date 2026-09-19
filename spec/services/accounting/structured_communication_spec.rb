require 'rails_helper'

RSpec.describe Accounting::StructuredCommunication do
  describe '.valid?' do
    it { expect(described_class.valid?('123456789002')).to be true }   # 1234567890 % 97 = 2
    it { expect(described_class.valid?('123456789003')).to be false }
    it 'accepts 97 as check when the remainder is 0' do
      expect(described_class.valid?('000000009797')).to be true         # 97 % 97 = 0 -> 97
    end
    it { expect(described_class.valid?('12345')).to be false }
  end

  describe '.extract' do
    it 'reads the +++ form' do
      expect(described_class.extract('Payment +++123/4567/89002+++ thanks')).to eq('123456789002')
    end
    it 'reads 12 bare digits' do
      expect(described_class.extract('ref 123456789002')).to eq('123456789002')
    end
    it 'ignores an invalid check digit' do
      expect(described_class.extract('+++123/4567/89003+++')).to be_nil
    end
    it { expect(described_class.extract(nil)).to be_nil }
  end

  describe '.for_id / .id_from' do
    it 'round-trips an invoice id' do
      digits = described_class.for_id(42)
      expect(described_class.valid?(digits)).to be true
      expect(described_class.id_from(digits)).to eq(42)
    end
    it 'formats with separators' do
      expect(described_class.display(described_class.for_id(42))).to match(%r{\A\+\+\+\d{3}/\d{4}/\d{5}\+\+\+\z})
    end
  end
end
