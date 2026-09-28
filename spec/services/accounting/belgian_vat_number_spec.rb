require "rails_helper"

# docs/dev/reports/spec.md §10 (R10): BE0/BE1 + 9 digits, the last two being 97 minus the
# remainder of the first eight digits divided by 97. No online VIES check (out of scope).
RSpec.describe Accounting::BelgianVatNumber do
  it "accepts a number whose check digits are right" do
    expect(described_class.valid?("BE0403170701")).to be(true) # 97 - (4031707 % 97) = 01
  end

  it "accepts the first digit 1 and lower/upper case, spaces and dots" do
    base = 12_345_678
    number = format("BE%08d%02d", base, 97 - (base % 97))
    expect(described_class.valid?(number)).to be(true)
    expect(described_class.valid?(number.downcase)).to be(true)
    expect(described_class.valid?("BE 0403.170.701")).to be(true)
  end

  it "rejects wrong check digits" do
    expect(described_class.valid?("BE0403170702")).to be(false)
  end

  it "rejects a wrong shape, another country, or blank" do
    [ "BE0403", "BE2403170701", "FR40303265045", "", nil ].each do |bad|
      expect(described_class.valid?(bad)).to be(false), bad.inspect
    end
  end
end
