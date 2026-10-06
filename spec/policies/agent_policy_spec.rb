require "rails_helper"

# The agent's rights (A03): a policy that only asks the matrix, like every other policy.
RSpec.describe AgentPolicy do
  include_context "with entity"

  it "denies a user with no membership in the entity, whatever the global role" do
    outsider = create(:user, role: :admin)

    expect(described_class.new(outsider, :agent).use?).to be false
  end

  it "gives a custom role the agent rights an owner chose (the external auditor, for instance)" do
    role = CustomRole.create!(name: "Agent asker", permissions: %w[agent.use])
    user = create(:user).tap { |u| create(:user_entity, user: u, entity: entity, role: :auditor, custom_role: role) }

    expect(described_class.new(user, :agent).use?).to be true
    expect(described_class.new(user, :agent).propose?).to be false
  end
end
