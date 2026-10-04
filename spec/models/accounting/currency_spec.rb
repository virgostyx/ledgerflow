require "rails_helper"

RSpec.describe Accounting::Currency, type: :model do
  it "holds every currency the application supports, with 0, 2 or 3 decimals" do
    expect(described_class.pluck(:code)).to match_array(Accounting::MoneyPresenter::SUPPORTED_CURRENCIES)
    expect(described_class.distinct.pluck(:decimals).sort).to eq([ 0, 2, 3 ])
  end

  it "knows the decimals of the yen (0), the euro and the dollar (2), the zambian kwacha (2) and the dinar of Bahrain (3)" do
    expect(%w[JPY EUR USD ZMW BHD].map { |code| described_class.decimals_of(code) }).to eq([ 0, 2, 2, 2, 3 ])
  end

  it "takes 2 decimals for a code it does not know" do
    expect(described_class.decimals_of("XXX")).to eq(2)
  end

  it "refuses a code that is not three capital letters, and a number of decimals other than 0, 2 or 3" do
    expect(described_class.new(code: "usd", decimals: 2)).not_to be_valid
    expect(described_class.new(code: "ABC", decimals: 4)).not_to be_valid
  end
end
