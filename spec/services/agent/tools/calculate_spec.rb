require "rails_helper"

# A05: every sum, difference and percentage of an answer goes through this tool, never through the model's head. Exact decimals, no float.
RSpec.describe Agent::Tools::Calculate do
  include_context "with entity"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :manager, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en) }
  let(:registry) { Agent::ToolRegistry.new([ described_class ]) }
  let(:tool) { described_class }
  let(:valid_args) { { "operation" => "sum", "values" => [ "10.00", "5.50" ] } }

  it_behaves_like "an agent tool", permission: "agent.use", denied_role: :auditor

  def calc(operation, values, precision = nil) = registry.execute("calculate", { "operation" => operation, "values" => values }.merge(precision ? { "precision" => precision } : {}), context)

  def result_of(operation, values, precision = nil) = calc(operation, values, precision)["data"].first["result"]

  it "adds exactly: no float error" do
    expect(result_of("sum", %w[0.10 0.20])).to eq("0.30")
    expect(result_of("sum", %w[1210.00 605.00 2420.00 363.00])).to eq("4598.00")
    expect(result_of("sum", %w[9999999999999.99 0.01])).to eq("10000000000000.00")
  end

  it "subtracts the second from the first, and multiplies two" do
    expect(result_of("difference", %w[3800.00 2300.00])).to eq("1500.00")
    expect(result_of("difference", %w[100.00 250.50])).to eq("-150.50")
    expect(result_of("multiply", %w[1000.00 0.21])).to eq("210.00")
  end

  it "divides, gives a percentage and a change in percent, rounded half up to the precision asked" do
    expect(result_of("ratio", %w[1 3])).to eq("0.33")
    expect(result_of("ratio", %w[1 3], 4)).to eq("0.3333")
    expect(result_of("percentage", %w[2178.00 4598.00], 1)).to eq("47.4")
    expect(result_of("change_percent", %w[2300.00 3450.00], 1)).to eq("50.0")
    expect(result_of("change_percent", %w[3.00 -1.50], 0)).to eq("-150")
    expect(result_of("sum", %w[0.005], 2)).to eq("0.01")
  end

  it "says what it did: the operation, the inputs and the precision, with a reference that stands for this very calculation" do
    row = calc("sum", %w[10.00 5.50])["data"].first

    expect(row).to include("operation" => "sum", "values" => %w[10.00 5.50], "precision" => 2, "result" => "15.50")
    expect(row["ref"]).to match(/\Acalc:\h{12}\z/)
    expect(calc("sum", %w[10.00 5.50])["data"].first["ref"]).to eq(row["ref"])
    expect(calc("sum", %w[10.00 5.60])["data"].first["ref"]).not_to eq(row["ref"])
  end

  it "wants two values where the operation is between two, and refuses a division by zero, with words" do
    expect(calc("difference", %w[1 2 3])).to include("error" => "invalid_arguments", "message" => a_string_including("exactly two"))
    expect(calc("ratio", %w[1])).to include("error" => "invalid_arguments")
    expect(calc("ratio", %w[1 0])).to include("error" => "invalid_arguments", "message" => a_string_including("zero"))
    expect(calc("change_percent", %w[0 5])).to include("error" => "invalid_arguments")
  end

  it "refuses a value that is not a decimal string, an operation it does not know, and a precision out of range" do
    expect(calc("sum", [ "1e5" ])).to include("error" => "invalid_arguments")
    expect(calc("sum", [ 1.5 ])).to include("error" => "invalid_arguments")
    expect(calc("power", %w[2 3])).to include("error" => "invalid_arguments")
    expect(calc("sum", %w[1 2], 7)).to include("error" => "invalid_arguments")
  end

  it "does no more than 50 values" do
    expect(calc("sum", Array.new(51) { "1.00" })).to include("error" => "invalid_arguments")
  end
end
