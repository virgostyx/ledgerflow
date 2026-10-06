require "rails_helper"

RSpec.describe Agent::Context do
  include_context "with entity"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, user: user, entity: entity, role: :accountant) }

  subject(:context) { described_class.build(user: user, entity: entity, locale: :fr, screen: "reports/aged_balance", subject_ref: { "type" => "R04", "id" => "p-1" }) }

  it "carries who asks, about which entity, on which day, in which language and where in the app" do
    expect(context).to have_attributes(user: user, entity: entity, locale: :fr, screen: "reports/aged_balance", subject_ref: { "type" => "R04", "id" => "p-1" })
    expect(context.today).to eq(Date.current)
  end

  it "cannot be changed once built" do
    expect { context.instance_variable_set(:@entity, create(:entity)) }.to raise_error(FrozenError)
  end

  it "reads the rights at every question, not once at the start of the conversation" do
    expect(context.allows?("agent.use")).to be true

    membership.update!(role: :auditor, valid_until: 1.month.from_now)

    expect(context.allows?("agent.use")).to be false
  end

  it "denies everything once the membership is gone" do
    membership.destroy!

    expect(context.allows?("reports.view")).to be false
  end

  it "knows an unknown permission is a bug, not a denial" do
    expect { context.allows?("agent.typo") }.to raise_error(KeyError)
  end
end
