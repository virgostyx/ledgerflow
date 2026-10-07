require "rails_helper"

# A03: every tool, for every role, answers as the permission matrix says: those who hold the permission are served (or told something else than a refusal, such as that nothing was
# found), the others get the same refusal, word for word, whatever exists behind it.
RSpec.describe "The rights of the agent's tools" do
  include_context "with_open_fiscal_year"

  ARGUMENTS = {
    "get_company_context" => {}, "search_accounts" => { "q" => "4" }, "search_partners" => { "q" => "a" }, "get_journal_entry" => { "id" => 1 },
    "get_trial_balance" => {}, "get_ledger" => { "account" => "400000" }, "get_aged_balance" => { "kind" => "customer" }, "list_unreconciled" => {},
    "get_bank_reconciliation" => {}, "get_financial_statements" => { "statement" => "income" }, "get_vat_return" => { "period_start" => "2026-01-01", "period_end" => "2026-03-31" },
    "get_dashboard_kpis" => {}, "get_consistency_findings" => {}, "get_audit_trail" => {}, "search_documents" => { "q" => "a" }, "search_knowledge" => { "query" => "prepayment" }, "get_finding_context" => { "finding_id" => 1 },
    "get_variation" => { "account_prefix" => "6", "first_from" => "2026-01-01", "first_to" => "2026-01-31", "second_from" => "2026-02-01", "second_to" => "2026-02-28" }, "calculate" => { "operation" => "sum", "values" => [ "1.00" ] }
  }.freeze

  let(:registry) { Agent::ToolRegistry.default }
  let(:tools) { registry.instance_variable_get(:@tools).values }

  def context_for(role)
    user = create(:user)
    create(:user_entity, user: user, entity: entity, role: role, valid_until: (1.year.from_now if role == :auditor))
    Agent::Context.build(user: user, entity: entity, locale: :en)
  end

  it "has valid arguments for every tool of the catalog, so that the matrix below misses none" do
    expect(ARGUMENTS.keys).to match_array(tools.map(&:tool_name))
  end

  UserEntity.roles.each_key do |role|
    describe "a person with the #{role} role" do
      Agent::ToolRegistry.default.instance_variable_get(:@tools).each_value do |tool|
        allowed = Permissions.allowed?(role.to_sym, tool.permission)

        it "#{allowed ? 'is served by' : 'is refused by'} #{tool.tool_name} (#{tool.permission})" do
          answer = registry.execute(tool.tool_name, ARGUMENTS.fetch(tool.tool_name), context_for(role.to_sym))

          if allowed
            expect(answer).not_to eq(Agent::ToolRegistry::FORBIDDEN)
          else
            expect(answer).to eq(Agent::ToolRegistry::FORBIDDEN)
          end
        end
      end
    end
  end

  it "refuses without a membership: a person who does not belong to the entity gets nothing, whatever their role elsewhere" do
    outsider = Agent::Context.build(user: create(:user), entity: entity, locale: :en)

    answers = tools.map { |tool| registry.execute(tool.tool_name, ARGUMENTS.fetch(tool.tool_name), outsider) }

    expect(answers).to all(eq(Agent::ToolRegistry::FORBIDDEN))
  end

  it "refuses once the access has expired, from the very next call" do
    user = create(:user)
    membership = create(:user_entity, user: user, entity: entity, role: :auditor, valid_until: 1.day.from_now)
    context = Agent::Context.build(user: user, entity: entity, locale: :en)
    expect(registry.execute("get_trial_balance", {}, context)).not_to eq(Agent::ToolRegistry::FORBIDDEN)

    membership.update_columns(valid_until: 2.days.ago.to_date) # access is by the day

    expect(registry.execute("get_trial_balance", {}, context)).to eq(Agent::ToolRegistry::FORBIDDEN)
  end

  it "serves the rights a custom role grants, and no others" do
    role = CustomRole.create!(name: "Journals only", permissions: %w[records.view])
    user = create(:user)
    create(:user_entity, user: user, entity: entity, role: :accountant, custom_role: role)
    context = Agent::Context.build(user: user, entity: entity, locale: :en)

    expect(registry.execute("search_accounts", { "q" => "4" }, context)).not_to eq(Agent::ToolRegistry::FORBIDDEN)
    expect(registry.execute("get_trial_balance", {}, context)).to eq(Agent::ToolRegistry::FORBIDDEN)
    expect(registry.execute("get_company_context", {}, context)).to eq(Agent::ToolRegistry::FORBIDDEN)
  end
end
