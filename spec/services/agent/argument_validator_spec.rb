require "rails_helper"

RSpec.describe Agent::ArgumentValidator do
  let(:schema) do
    { type: "object", additionalProperties: false, required: %w[kind],
      properties: { kind: { type: "string", enum: %w[customer supplier] },
                    as_of: { type: "string", format: "date" },
                    limit: { type: "integer", minimum: 1, maximum: 100 },
                    q: { type: "string", maxLength: 10 },
                    include_zero: { type: "boolean" } } }
  end

  def problems(args) = described_class.problems(schema, args)

  it "accepts arguments that keep to the schema" do
    expect(problems({ "kind" => "customer", "as_of" => "2026-09-26", "limit" => 10, "q" => "acme", "include_zero" => true })).to be_empty
  end

  it "refuses an argument the schema does not name, which is how company_id and the like are turned away" do
    expect(problems({ "kind" => "customer", "company_id" => 7 })).to eq([ "company_id is not an argument of this tool" ])
  end

  it "refuses a missing required argument" do
    expect(problems({})).to eq([ "kind is required" ])
  end

  it "refuses a value outside the list, the range, the length or the type" do
    expect(problems({ "kind" => "other" })).to include(/kind must be one of customer, supplier/)
    expect(problems({ "kind" => "customer", "limit" => 0 })).to include(/limit must be between 1 and 100/)
    expect(problems({ "kind" => "customer", "limit" => 101 })).to include(/limit must be between 1 and 100/)
    expect(problems({ "kind" => "customer", "q" => "x" * 11 })).to include(/q is too long/)
    expect(problems({ "kind" => "customer", "limit" => "10" })).to include(/limit must be an integer/)
    expect(problems({ "kind" => "customer", "include_zero" => "yes" })).to include(/include_zero must be true or false/)
  end

  it "refuses a date that is not an ISO 8601 date, or does not exist" do
    expect(problems({ "kind" => "customer", "as_of" => "26/09/2026" })).to include(/as_of must be a date/)
    expect(problems({ "kind" => "customer", "as_of" => "2026-02-30" })).to include(/as_of must be a date/)
  end

  describe "a list" do
    let(:schema) { { type: "object", additionalProperties: false, properties: { values: { type: "array", minItems: 1, maxItems: 3, items: { type: "string", pattern: "^-?\\d+(\\.\\d+)?$" } } } } }

    it "accepts a list within its bounds, whose items keep to their own rule" do
      expect(described_class.problems(schema, { "values" => [ "1.50", "-2" ] })).to be_empty
    end

    it "refuses what is not a list, a list too short or too long, and an item that does not keep to its rule, naming the item" do
      expect(described_class.problems(schema, { "values" => "1.50" })).to include("values must be a list")
      expect(described_class.problems(schema, { "values" => [] })).to include("values must have at least 1 item(s)")
      expect(described_class.problems(schema, { "values" => %w[1 2 3 4] })).to include("values must have at most 3 item(s)")
      expect(described_class.problems(schema, { "values" => [ "1", "abc" ] })).to eq([ "values[1] does not have the expected form" ])
      expect(described_class.problems(schema, { "values" => [ 1 ] })).to eq([ "values[0] must be a string" ])
    end
  end

  it "reads arguments given with symbol keys as well" do
    expect(problems({ kind: "customer" })).to be_empty
  end
end
