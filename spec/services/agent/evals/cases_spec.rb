require "rails_helper"

# A12: the volume of the cases, and what each one needs to be worth keeping.
RSpec.describe "The cases of the evaluation" do
  let(:cases) { Agent::Evals::Case.load(Agent::Evals::Runner::CASE_FILES, facts: Agent::Evals::Dataset.facts, ids: Agent::Evals::Dataset.ids(Agent::Evals::Dataset.build!)) }

  it "has the thirty cases of the first wave, with unique identifiers" do
    expect(cases.size).to eq(30)
    expect(cases.map(&:id).uniq.size).to eq(30)
  end

  it "covers the capabilities of the wave: the tools, the figures, the attacks and what is sent" do
    expect(cases.group_by(&:capability).transform_values(&:size)).to eq("A02" => 14, "A03" => 6, "A04" => 5, "A05" => 5)
  end

  it "has a case for every tool of the catalog but the bank reconciliation, which needs a bank account the dataset does not have yet" do
    named = cases.flat_map { |kase| Array(kase.expect["tools"]).map { |want| want["name"] } }.uniq

    expect(Agent::ToolRegistry.default.definitions.map { |definition| definition[:name] } - named).to eq([ "get_bank_reconciliation" ])
  end

  it "keeps a case's figures to the facts of the dataset, never typed twice: no amount is written in a case" do
    typed = Agent::Evals::Runner::CASE_FILES.flat_map { |file| File.read(file).lines.reject { |line| line.strip.start_with?("#") }.grep(/\d[.,]\d{2}\b/) }

    expect(typed.reject { |line| line.include?("{{facts.") || line.include?("EUR 0.00") }).to be_empty
  end

  it "gives each case a person with the right to ask what it asks, or says it expects a refusal" do
    refusals = cases.select { |kase| Array(kase.expect["tool_errors"]).include?("forbidden") }

    expect(refusals.map(&:role).uniq).to eq([ "reader" ])
    expect(cases.reject { |kase| kase.role == "reader" }.size).to be > 20
  end
end
