require "rails_helper"

# B01b: the small rules a payment file depends on - which days the banks settle, and which characters a SEPA file may carry.
RSpec.describe Payments::SettlementCalendar do
  it "settles on weekdays only" do
    expect(described_class.open?(Date.new(2026, 10, 12))).to be true  # Monday
    expect(described_class.open?(Date.new(2026, 10, 16))).to be true  # Friday
    expect(described_class.open?(Date.new(2026, 10, 17))).to be false # Saturday
    expect(described_class.open?(Date.new(2026, 10, 18))).to be false # Sunday
  end

  it "does not settle on the TARGET holidays: 1 January, Good Friday, Easter Monday, 1 May, 25 and 26 December" do
    {
      Date.new(2026, 1, 1) => "New Year", Date.new(2026, 4, 3) => "Good Friday 2026", Date.new(2026, 4, 6) => "Easter Monday 2026",
      Date.new(2026, 5, 1) => "Labour Day", Date.new(2026, 12, 25) => "Christmas", Date.new(2026, 12, 26) => "St Stephen",
      Date.new(2027, 3, 26) => "Good Friday 2027", Date.new(2027, 3, 29) => "Easter Monday 2027"
    }.each { |day, name| expect(described_class.open?(day)).to be(false), name }
    expect(described_class.open?(Date.new(2026, 4, 2))).to be true # Maundy Thursday: banks settle
  end

  it "takes the closed days a bank adds to its profile" do
    expect(described_class.open?(Date.new(2026, 11, 11))).to be true
    expect(described_class.open?(Date.new(2026, 11, 11), extra_closed: [ "2026-11-11" ])).to be false
  end

  it "finds the next day it settles" do
    expect(described_class.next_open(Date.new(2026, 10, 17))).to eq(Date.new(2026, 10, 19))
    expect(described_class.next_open(Date.new(2026, 12, 24))).to eq(Date.new(2026, 12, 24))
    expect(described_class.next_open(Date.new(2026, 12, 25))).to eq(Date.new(2026, 12, 28))
  end
end

RSpec.describe Payments::SepaText do
  it "keeps what the SEPA character set allows" do
    expect(described_class.clean("Invoice 12/2026 (Acme-Ltd): +10,5 'x'")).to eq("Invoice 12/2026 (Acme-Ltd): +10,5 'x'")
  end

  it "turns accents into their letters, and what has no letter into a space" do
    expect(described_class.clean("Café Müller & Fils – Brüssel")).to eq("Cafe Muller   Fils   Brussel")
    expect(described_class.clean("Ærø Straße")).to eq("AEro Strasse")
  end

  it "says what it changed, so that a person sees it before the file goes out" do
    changes = described_class.changes("Café Müller & Co")

    expect(changes).to eq([ "Café Müller & Co" => "Cafe Muller   Co" ].first)
    expect(described_class.changes("Plain Name")).to be_nil
  end

  it "is deterministic and never makes a text longer than the limit it is given" do
    expect(described_class.clean("é" * 50, max: 35).length).to eq(35)
    expect(described_class.clean("Café")).to eq(described_class.clean("Café"))
  end
end
