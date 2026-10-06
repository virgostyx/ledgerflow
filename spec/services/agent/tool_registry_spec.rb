require "rails_helper"

RSpec.describe Agent::ToolRegistry do
  include_context "with entity"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, user: user, entity: entity, role: :manager) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en) }

  let(:tool) do
    Class.new(Agent::Tools::Base) do
      tool_name "echo"
      description "Repeats what it is given. Use it to test."
      permission "reports.view"
      input_schema type: "object", properties: { text: { type: "string" } }, required: %w[text], additionalProperties: false

      def call(args, _context) = { "data" => args["text"] }
    end
  end

  subject(:registry) { described_class.new([ tool ]) }

  it "describes its tools to the model, with a strict schema" do
    expect(registry.definitions).to eq([ { name: "echo", description: "Repeats what it is given. Use it to test.", strict: true,
                                           input_schema: { type: "object", properties: { text: { type: "string" } }, required: %w[text], additionalProperties: false } } ])
  end

  it "runs a tool for a person who may read what it reads" do
    expect(registry.execute("echo", { "text" => "hi" }, context)).to eq("data" => "hi")
  end

  it "answers forbidden, and nothing else, when the person lacks the permission" do
    membership.update!(role: :auditor, valid_until: 1.month.from_now) # may read reports
    allow(tool).to receive(:permission).and_return("agent.configure")

    expect(registry.execute("echo", { "text" => "hi" }, context)).to eq("error" => "forbidden", "message" => "You do not have access to this information.")
  end

  it "turns away arguments that do not keep to the schema, without running the tool, and says what is wrong" do
    result = registry.execute("echo", { "text" => "hi", "company_id" => 7 }, context)

    expect(result).to eq("error" => "invalid_arguments", "message" => "company_id is not an argument of this tool")
  end

  it "answers timeout when a tool takes longer than it may, instead of keeping the person waiting" do
    slow = Class.new(tool) { def call(*) = sleep(2) }

    result = described_class.new([ slow ], timeout: 0.05).execute("echo", { "text" => "x" }, context)

    expect(result).to include("error" => "timeout")
  end

  it "answers not_found for a tool it does not have" do
    expect(registry.execute("drop_table", {}, context)).to include("error" => "not_found")
  end

  it "turns a failing tool into an error result without any internal detail" do
    boom = Class.new(tool) { def call(*) = raise("PG::Error: secret detail") }

    result = described_class.new([ boom ]).execute("echo", { "text" => "x" }, context)

    expect(result).to include("error" => "internal_error")
    expect(result.to_s).not_to include("secret detail")
  end
end
