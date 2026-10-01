require "rails_helper"

RSpec.describe Accounting::Settings::BasePolicy, type: :policy do
  include_context "with entity"

  # Rights come from the role held in the current entity (F01); budget_user has no entity role.
  let(:admin)       { member(:admin) }
  let(:accountant)  { member(:accountant) }
  let(:manager)     { member(:manager) }
  let(:auditor)     { member(:auditor) }
  let(:budget_user) { create(:user, role: :budget_user) }

  def member(role)
    create(:user, role: role).tap { |user| create(:user_entity, user: user, entity: entity, role: role) }
  end

  def policy_for(user)
    described_class.new(user, :settings)
  end

  describe "admin" do
    subject(:policy) { policy_for(admin) }

    it { expect(policy.index?).to be true }
    it { expect(policy.create?).to be true }
    it { expect(policy.update?).to be true }
    it { expect(policy.destroy?).to be true }
  end

  describe "accountant" do
    subject(:policy) { policy_for(accountant) }

    it { expect(policy.index?).to be true }
    it { expect(policy.create?).to be true }
    it { expect(policy.update?).to be true }
    it { expect(policy.destroy?).to be false }
  end

  describe "manager" do
    subject(:policy) { policy_for(manager) }

    it { expect(policy.index?).to be false }
    it { expect(policy.create?).to be false }
    it { expect(policy.update?).to be false }
    it { expect(policy.destroy?).to be false }
  end

  describe "auditor" do
    subject(:policy) { policy_for(auditor) }

    it { expect(policy.index?).to be false }
    it { expect(policy.create?).to be false }
    it { expect(policy.update?).to be false }
    it { expect(policy.destroy?).to be false }
  end

  describe "budget_user" do
    subject(:policy) { policy_for(budget_user) }

    it { expect(policy.index?).to be false }
    it { expect(policy.create?).to be false }
    it { expect(policy.update?).to be false }
    it { expect(policy.destroy?).to be false }
  end
end
