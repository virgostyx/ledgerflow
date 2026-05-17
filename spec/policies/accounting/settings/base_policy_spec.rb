require "rails_helper"

RSpec.describe Accounting::Settings::BasePolicy, type: :policy do
  let(:admin)       { build_stubbed(:user, role: :admin) }
  let(:accountant)  { build_stubbed(:user, role: :accountant) }
  let(:manager)     { build_stubbed(:user, role: :manager) }
  let(:auditor)     { build_stubbed(:user, role: :auditor) }
  let(:budget_user) { build_stubbed(:user, role: :budget_user) }

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
