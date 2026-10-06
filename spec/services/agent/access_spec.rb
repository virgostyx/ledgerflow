require "rails_helper"

RSpec.describe Agent::Access do
  include_context "with entity"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, user: user, entity: entity, role: :accountant) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en) }

  def turn_on! = enable_agent!(entity)

  around do |example|
    previous = ENV.delete("AGENT_KILL_SWITCH")
    example.run
  ensure
    previous ? ENV["AGENT_KILL_SWITCH"] = previous : ENV.delete("AGENT_KILL_SWITCH")
  end

  it "lets in a person with the right, on an entity where the feature and the setting are on" do
    turn_on!

    expect(described_class.check(context)).to be_nil
  end

  {
    "the agent feature of the entity is off" => ->(s) { s.entity.update!(features: s.entity.features.merge("agent" => false)) },
    "the owner has not turned the agent on"   => ->(s) { Agent::Setting.for_current_entity.update!(enabled: false) },
    "the emergency switch is on"              => ->(_) { ENV["AGENT_KILL_SWITCH"] = "1" },
    "the owner has not accepted the current terms"  => ->(_) { Agent::Consent.delete_all },
    "the person has no right to use the agent" => ->(s) { s.membership.update!(role: :auditor, valid_until: 1.month.from_now) }
  }.each do |reason, break_it|
    it "refuses when #{reason}" do
      turn_on!
      break_it.call(self)

      expect(described_class.check(context)).to be_present
      expect { described_class.check!(context) }.to raise_error(Agent::Unavailable)
    end
  end

  it "stays off for a text of the terms that was not accepted, even if an older one was" do
    turn_on!
    Agent::Consent.update_all(version: "2020-01-01")

    expect(described_class.check(context)).to eq(:consent_missing)
  end

  it "names why, without technical detail" do
    ENV["AGENT_KILL_SWITCH"] = "1"

    expect(described_class.check(context)).to eq(:disabled_platform)
  end
end
