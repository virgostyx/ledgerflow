require "rails_helper"

RSpec.describe Accounting::Iban do
  it "accepts a valid IBAN, with or without spaces and in any case" do
    expect(described_class.valid?("BE68539007547034")).to be true
    expect(described_class.valid?("BE68 5390 0754 7034")).to be true
    expect(described_class.valid?("be68 5390 0754 7034")).to be true
    expect(described_class.valid?("DE89 3704 0044 0532 0130 00")).to be true
    expect(described_class.valid?("FR14 2004 1010 0505 0001 3M02 606")).to be true
  end

  it "refuses a wrong check, a wrong length, junk and blank" do
    [ "BE68539007547035", "BE6853900754703", "BE68 5390 0754 7034 99", "XX00", "", nil, "hello world" ].each do |bad|
      expect(described_class.valid?(bad)).to be(false), "expected #{bad.inspect} to be refused"
    end
  end

  it "writes an IBAN in its canonical form" do
    expect(described_class.normalize("be68 5390 0754 7034")).to eq("BE68539007547034")
  end
end
