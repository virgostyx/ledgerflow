require "rails_helper"

# F11, the convention: a rate is the number of units of foreign currency for 1 EUR; EUR = foreign / rate (criteria 1 and 6).
RSpec.describe Fx::Convert do
  describe ".to_eur" do
    it "divides the foreign amount by the rate: 1 000 USD at 1.10 are 909.09 EUR" do
      expect(described_class.to_eur(BigDecimal("1000"), BigDecimal("1.10"))).to eq(BigDecimal("909.09"))
    end

    it "is not inverted: the same figures multiplied would give 1 100.00, which is the mistake this test is here to catch" do
      expect(described_class.to_eur(BigDecimal("1000"), BigDecimal("1.10"))).not_to eq(BigDecimal("1100.00"))
      expect(described_class.to_eur(BigDecimal("1000"), BigDecimal("1.10"))).to be < BigDecimal("1000")
    end

    it "gives a smaller sum of euros for a currency that is worth less (25 ZMW for 1 EUR)" do
      expect(described_class.to_eur(BigDecimal("1000"), BigDecimal("25"))).to eq(BigDecimal("40.00"))
    end

    it "keeps the sign" do
      expect(described_class.to_eur(BigDecimal("-1000"), BigDecimal("1.10"))).to eq(BigDecimal("-909.09"))
    end

    it "rounds half up to the cent, on the exact quotient and not on a rounded rate" do
      expect(described_class.to_eur(BigDecimal("1"), BigDecimal("3"))).to eq(BigDecimal("0.33"))
      expect(described_class.to_eur(BigDecimal("0.01"), BigDecimal("2"))).to eq(BigDecimal("0.01")) # 0.005 -> 0.01
      expect(described_class.to_eur(BigDecimal("100"), BigDecimal("1.23456789"))).to eq(BigDecimal("81.00"))
    end

    it "is the identity for EUR (rate 1)" do
      expect(described_class.to_eur(BigDecimal("12.34"), BigDecimal("1"))).to eq(BigDecimal("12.34"))
    end

    it "refuses a rate that is zero or negative" do
      expect { described_class.to_eur(BigDecimal("1"), BigDecimal("0")) }.to raise_error(ArgumentError, /rate/)
      expect { described_class.to_eur(BigDecimal("1"), BigDecimal("-1.1")) }.to raise_error(ArgumentError, /rate/)
    end
  end
end
