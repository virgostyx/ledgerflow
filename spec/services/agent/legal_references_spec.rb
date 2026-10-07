require "rails_helper"

RSpec.describe Agent::LegalReferences do
  it "reads an article whatever the way it is written" do
    expect(described_class.keys("See Article 45 bis, art. 45bis and artikel 45 bis.")).to eq([ "article:45bis" ])
    expect(described_class.keys("art. 3:12, Art 7")).to eq([ "article:3:12", "article:7" ])
  end

  it "reads a law, a decree and a circular by their year or number" do
    text = "La loi du 15 mars 2007, the royal decree of 12/05/1992, la circulaire 2021/C/45, omzendbrief van 2019"

    expect(described_class.keys(text)).to eq(%w[law:2007 decree:1992 circular:2021/c/45 circular:2019])
  end

  it "does not take a sentence that merely mentions a year for a reference" do
    expect(described_class.keys("The law is clear. In 2026 we act on 2026 entries; the AR is in a drawer.")).to eq([])
  end

  it "gives the position of each, to mark it in place" do
    text = "Under art. 45 it holds."

    match = described_class.matches(text).first

    expect(text[match.position, match.length]).to eq("art. 45")
  end
end
