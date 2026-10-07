require "rails_helper"

# A08: a step of a correction points to a screen of the application; the link is made from this table, and every entry must open a route that exists.
RSpec.describe Agent::Screens do
  it "has a path for every screen, and the path is built by a route helper of the application" do
    described_class.names.each do |name|
      path = described_class.path(name)

      expect(path).to start_with("/accounting/")
    end
  end

  it "is a reference like any other: it opens its screen, says what it is, and an unknown one opens nothing" do
    expect(Agent::Refs.path(described_class.ref("lettering"))).to eq(described_class.path("lettering"))
    expect(Agent::Refs.label("screen:vat")).to eq("Screen: VAT returns")
    expect(Agent::Refs.path("screen:nowhere")).to be_nil
  end
end
