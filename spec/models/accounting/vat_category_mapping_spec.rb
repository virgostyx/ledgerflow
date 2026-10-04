require "rails_helper"

RSpec.describe Accounting::VatCategoryMapping do
  include_context "with entity"

  it "readies S, Z, E and O as ordinary purchases, once, and leaves AE, K and G to the accountant" do
    2.times { described_class.ensure_defaults! }

    expect(described_class.pluck(:category)).to match_array(%w[S Z E O])
    expect(described_class.pluck(:vat_treatment).uniq).to eq([ "domestic" ])
  end

  it "does not bring a category back once the entity unmapped it (the defaults are made once)" do
    described_class.ensure_defaults!
    described_class.find_by(category: "E").destroy!
    described_class.ensure_defaults!

    expect(described_class.pluck(:category)).to match_array(%w[S Z O])
  end

  it "leaves what the entity changed" do
    described_class.create!(category: "E", vat_treatment: :exempt)
    described_class.ensure_defaults!

    expect(described_class.find_by(category: "E")).to be_exempt
  end

  it "keeps a category once per entity, and only the categories of UBL" do
    described_class.create!(category: "AE", vat_treatment: :construction_reverse_charge, vat_rate: 21)

    expect(described_class.new(category: "AE", vat_treatment: :domestic)).not_to be_valid
    expect(described_class.new(category: "X", vat_treatment: :domestic)).not_to be_valid
    other = create(:entity)
    ActsAsTenant.with_tenant(other) { expect(described_class.new(category: "AE", vat_treatment: :domestic)).to be_valid }
  end

  it "takes a rate to self-assess, never a negative one" do
    expect(described_class.new(category: "AE", vat_treatment: :construction_reverse_charge, vat_rate: -1)).not_to be_valid
  end
end
