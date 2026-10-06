require "rails_helper"

RSpec.describe Agent::Setting do
  include_context "with entity"

  it "is off, with 90 days of retention, until an owner says otherwise" do
    setting = described_class.for_current_entity

    expect(setting).to have_attributes(enabled: false, retention_days: 90, entity: entity)
  end

  it "is one row per entity, found again and not duplicated" do
    expect { 2.times { described_class.for_current_entity } }.to change(described_class, :count).by(1)
  end

  it "keeps the retention to the choices of the spec" do
    expect(described_class.new(retention_days: 90)).to be_valid
    expect(described_class.new(retention_days: 7)).not_to be_valid
  end
end
