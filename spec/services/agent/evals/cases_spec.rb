require "rails_helper"

# A12: the volume of the cases, and what each one needs to be worth keeping.
RSpec.describe "The cases of the evaluation" do
  let(:cases) { Agent::Evals::Case.load(Agent::Evals::Runner::CASE_FILES, facts: Agent::Evals::Dataset.facts, ids: Agent::Evals::Dataset.ids(Agent::Evals::Dataset.build!)) }

  it "has the cases of the capabilities delivered so far, with unique identifiers" do
    expect(cases.size).to eq(182)
    expect(cases.map(&:id).uniq.size).to eq(182)
  end

  it "covers the capabilities delivered: the tools, the attacks, what is sent, and the figures, with the volume the specification asks for each" do
    sizes = cases.group_by(&:capability).transform_values(&:size)

    expect(sizes).to eq("A02" => 14, "A03" => 6, "A04" => 5, "A05" => 67, "A06" => 38, "A08" => 28, "A07" => 24)
    expect(sizes["A05"]).to be >= 60 # §15: at least 60 cases for A05
  end

  it "writes A05's questions in more than one language, since the people who ask do" do
    expect(cases.select { |kase| kase.capability == "A05" }.map(&:language).uniq).to contain_exactly("en", "fr", "nl")
  end

  it "has cases for what a model does wrong, and for what the assistant must refuse to do" do
    tags = cases.flat_map(&:tags)

    expect(tags).to include("anchoring", "citations", "calculation", "relative_dates", "ambiguity", "truncated", "absence", "rights")
  end

  it "has a case for every tool of the catalog but the bank reconciliation, which needs a bank account the dataset does not have yet" do
    named = cases.flat_map { |kase| Array(kase.expect["tools"]).map { |want| want["name"] } }.uniq

    expect(Agent::ToolRegistry.default.definitions.map { |definition| definition[:name] } - named).to eq([ "get_bank_reconciliation" ])
  end

  it "keeps a case's figures to the facts of the dataset, never typed twice: no amount is written in a case" do
    typed = Agent::Evals::Runner::CASE_FILES.flat_map { |file| File.read(file).lines.reject { |line| line.strip.start_with?("#") }.grep(/\d[.,]\d{2}\b/) }

    invented = %w[9999.99 8888.88 777.00 888.00 500.00] # the amounts a misbehaving model makes up, which no fact stands for
    expect(typed.reject { |line| line.include?("{{facts.") || invented.any? { |amount| line.include?(amount) } }).to be_empty
  end

  it "gives each case a person with the right to ask what it asks, or says it expects a refusal" do
    refusals = cases.select { |kase| Array(kase.expect["tool_errors"]).include?("forbidden") }

    expect(refusals.map(&:role).uniq).to eq([ "reader" ])
    expect(cases.reject { |kase| kase.role == "reader" }.size).to be > 20
  end
end
