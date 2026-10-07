require "rails_helper"

RSpec.describe Agent::Examples do
  it "gives questions fitted to the screen the panel was opened on" do
    expect(described_class.for("accounting/reports#aged_balance")).to include("Who owes the most?")
    expect(described_class.for("accounting/vat_declarations#index").first).to include("VAT")
    expect(described_class.for("accounting/consistency_runs#index")).to include("What should I fix first?")
  end

  it "gives general questions for any other screen, or none" do
    expect(described_class.for("accounting/dashboard#index")).to eq(described_class::GENERIC)
    expect(described_class.for(nil)).to eq(described_class::GENERIC)
  end

  it "gives a few, never a wall of them" do
    (described_class::BY_SCREEN.values + [ described_class::GENERIC ]).each { |questions| expect(questions.size).to be_between(2, 3) }
  end
end
