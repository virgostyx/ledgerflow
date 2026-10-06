# What every tool of the agent must satisfy (A02 §5), written once. The including spec gives: `tool` (the class), `valid_args`, and an entity with a person who holds the right
# (`context`, `registry`). Options: `permission:` the matrix line it needs; `denied_role:` a role that lacks it, when there is one.
RSpec.shared_examples "an agent tool" do |permission:, denied_role: nil|
  def deep_values(value)
    case value
    when Hash  then value.values.flat_map { |inner| deep_values(inner) }
    when Array then value.flat_map { |inner| deep_values(inner) }
    else [ value ]
    end
  end

  it "has a snake_case name, and a description that says when to use it and when not to" do
    expect(tool.tool_name).to match(/\A[a-z][a-z0-9_]*\z/)
    expect(tool.description).to include("Use ").and include("Do not use")
  end

  it "declares a strict schema: an object that names its arguments and refuses any other" do
    schema = tool.input_schema

    expect(schema).to include(type: "object", additionalProperties: false)
    expect(schema[:properties].keys.map(&:to_s)).not_to include("company_id", "entity_id", "user_id")
    expect(tool.definition).to include(strict: true)
  end

  it "needs #{permission}, a line of the permission matrix" do
    expect(tool.permission).to eq(permission)
    expect { Permissions.allowed?(:admin, tool.permission) }.not_to raise_error
  end

  it "turns away a company_id, an entity_id or a user_id, whoever gives it" do
    %w[company_id entity_id user_id].each do |forbidden|
      result = registry.execute(tool.tool_name, valid_args.merge(forbidden => 1), context)

      expect(result).to include("error" => "invalid_arguments")
    end
  end

  it "answers in the standard envelope, with amounts as strings and no Float anywhere" do
    result = registry.execute(tool.tool_name, valid_args, context)

    expect(result).not_to include("error")
    expect(result).to include("data", "row_count", "truncated", "filters_applied")
    expect(deep_values(result).grep(Float)).to be_empty
    expect(result.to_json.bytesize).to be <= Agent::ToolResult::MAX_BYTES
  end

  it "puts references on its values, and every one of them opens a screen" do
    refs = Agent::Refs.in_result(registry.execute(tool.tool_name, valid_args, context))

    expect(refs).not_to be_empty
    expect(refs.map { |ref| Agent::Refs.path(ref) }).to all(be_present)
  end

  it "classes the data it returns, so that the redactor knows what it handles" do
    expect(tool.field_classes).to be_a(Hash)
    expect(tool.field_classes.values - Agent::Tools::Base::FIELD_CLASSES).to be_empty
  end

  it "writes nothing to the books" do
    tables = %w[accounting_journal_entries accounting_journal_entry_lines accounting_accounts accounting_partners accounting_period_locks accounting_letterings]
    counts = -> { tables.map { |table| ActiveRecord::Base.connection.select_value("SELECT count(*) FROM #{table}") } }

    expect { registry.execute(tool.tool_name, valid_args, context) }.not_to change { counts.call }
  end

  if denied_role
    it "answers forbidden to a person without #{permission}, and says nothing of what exists" do
      UserEntity.find_by(user: context.user).update!(role: denied_role, valid_until: 1.month.from_now)

      expect(registry.execute(tool.tool_name, valid_args, context)).to eq(Agent::ToolRegistry::FORBIDDEN)
    end
  end
end
