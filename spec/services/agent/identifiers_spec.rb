require "rails_helper"

RSpec.describe Agent::Identifiers do
  def national_number(base) = "#{base}#{format('%02d', 97 - base.to_i % 97)}"

  it "finds only the IBANs whose check digits are right" do
    expect(described_class.ibans("pay BE68 5390 0754 7034 or BE68 5390 0754 7035 or DE89370400440532013000")).to eq([ [ "BE68 5390 0754 7034", "BE68539007547034" ], [ "DE89370400440532013000", "DE89370400440532013000" ] ])
  end

  it "checks a Belgian national number the way the register does, for the two centuries" do
    expect(described_class.national_number?(national_number("850731001"))).to be true
    expect(described_class.national_number?("85.07.31-001.#{format('%02d', 97 - 850731001 % 97)}")).to be true
    expect(described_class.national_number?(national_number("850731001").sub(/.\z/) { |digit| ((digit.to_i + 1) % 10).to_s })).to be false
    expect(described_class.national_number?("12345")).to be false
  end

  it "checks a Belgian company number" do
    valid = "0#{format('%07d', 1_234_567)}#{format('%02d', 97 - 1_234_567 % 97)}"

    expect(described_class.belgian_company_number?(valid)).to be true
    expect(described_class.belgian_company_number?("BE #{valid}")).to be true
    expect(described_class.belgian_company_number?("0123456780")).to be false
  end

  it "checks a card number with Luhn" do
    expect(described_class.card?("4111 1111 1111 1111")).to be true
    expect(described_class.card?("4111 1111 1111 1112")).to be false
    expect(described_class.card?("12345")).to be false
  end
end
