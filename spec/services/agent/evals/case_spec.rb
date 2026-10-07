require "rails_helper"

RSpec.describe Agent::Evals::Case do
  let(:facts) { { "customers_total" => "4598.00" } }
  let(:ids) { { "acme" => "42" } }

  def write(yaml)
    Tempfile.create([ "cases", ".yml" ]) { |file| file.write(yaml); file.flush; yield file.path }
  end

  def raw(extra = {}) = { "id" => "T-1", "capability" => "A05", "role" => "accountant", "source" => "reference_dataset", "input" => "Q?", "script" => [ { "say" => "A" } ] }.merge(extra)

  it "loads the cases of a file, with the facts and identifiers in their place" do
    write([ raw("input" => "Is it {{facts.customers_total}}?", "script" => [ { "tool" => "t", "args" => { "id" => "{{ids.acme}}", "label" => "n{{ids.acme}}" } }, { "say" => "A" } ]) ].to_yaml) do |path|
      kase = described_class.load(path, facts: facts, ids: ids).first

      expect(kase.input).to eq("Is it 4598.00?")
      expect(kase.script.first["args"]).to eq("id" => 42, "label" => "n42") # an identifier that is a whole argument is a number
    end
  end

  it "refuses a placeholder that names nothing" do
    write([ raw("input" => "{{facts.nothing}}") ].to_yaml) { |path| expect { described_class.load(path, facts: facts, ids: ids) }.to raise_error(ArgumentError, /unknown placeholder/) }
  end

  it "refuses a case that is badly formed, and says what is wrong" do
    {
      raw("capability" => "X1") => "capability", raw("role" => "boss") => "role", raw("source" => "gossip") => "source", raw("input" => " ") => "input",
      raw("expect" => { "magic" => 1 }) => "unknown expectation", raw("script" => [ { "tool" => "t" } ]) => "ends with a say"
    }.each do |bad, word|
      write([ bad ].to_yaml) { |path| expect { described_class.load(path, facts: facts, ids: ids) }.to raise_error(ArgumentError, /#{word}/) }
    end
  end

  it "refuses two cases with the same id" do
    write([ raw, raw ].to_yaml) { |path| expect { described_class.load(path, facts: facts, ids: ids) }.to raise_error(ArgumentError, /used twice: T-1/) }
  end

  it "knows an attack and a tool choice by their tags" do
    write([ raw("tags" => %w[attack tool_choice]) ].to_yaml) do |path|
      kase = described_class.load(path, facts: facts, ids: ids).first

      expect(kase).to be_attack
      expect(kase).to be_tool_choice
    end
  end
end
