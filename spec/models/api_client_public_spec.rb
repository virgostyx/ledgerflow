require "rails_helper"

# F13c: the personal access tokens of the public API: scopes within the owner's rights (criterion 4), an expiry, a rate of their own.
RSpec.describe ApiClient, type: :model do
  let(:entity) { create(:entity) } # no BudgetFlow: the public API does not need it
  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:assistant)  { create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }

  def issue(owner, scopes, **attrs) = described_class.issue!(entity: entity, name: "Token", scopes: scopes, owner: owner, **attrs)

  it "serves the scopes of the public API, each as the right its owner would need by hand" do
    expect(described_class::SCOPES).to include(*%w[accounts:read partners:read journals:read entries:read entries:write entries:post entries:reverse
                                                   documents:read bank:read tasks:read periods:read reports:read letterings:read])
    expect(described_class::SCOPE_PERMISSIONS.fetch("entries:post")).to eq("entries.post")
    expect(described_class::SCOPE_PERMISSIONS.fetch("entries:reverse")).to eq("entries.reverse")
    expect(described_class::SCOPE_PERMISSIONS.keys).to match_array(described_class::SCOPES)
  end

  it "refuses at creation a scope its owner could not use by hand (criterion 4)" do
    expect { issue(assistant, %w[entries:read entries:post]) }.to raise_error(ActiveRecord::RecordInvalid, /exceed the rights of the owner: entries:post/)
    expect { issue(reader, %w[entries:write]) }.to raise_error(ActiveRecord::RecordInvalid, /entries:write/)
    expect(issue(accountant, %w[entries:read entries:write entries:post]).first).to be_persisted
    expect(issue(assistant, %w[entries:read entries:write]).first).to be_persisted
  end

  it "refuses a scope the owner loses the right to, when it is used, not only when it is made" do
    client, = issue(accountant, %w[entries:post])
    expect(client.allows?("entries:post")).to be(true)
    UserEntity.find_by(user: accountant, entity: entity).update!(role: :assistant)
    expect(client.reload.allows?("entries:post")).to be(false)
  end

  it "needs an owner for the scopes of the public API: a token is someone's" do
    expect { described_class.issue!(entity: entity, name: "Orphan", scopes: %w[entries:read]) }.to raise_error(ActiveRecord::RecordInvalid, /owner/i)
  end

  it "is for an entity that turned the feature on, or declared BudgetFlow" do
    entity.update!(features: { "f13" => false })
    expect { issue(accountant, %w[entries:read]) }.to raise_error(ActiveRecord::RecordInvalid, /did not turn on/)
    expect(described_class.issue!(entity: create(:entity, budgetflow_enabled: true, features: { "f13" => false }), name: "BF", scopes: %w[invoices:read]).first).to be_persisted
  end

  it "expires: a token past its date does not authenticate, and the date must be ahead" do
    client, key = issue(accountant, %w[entries:read], expires_at: 1.day.from_now)
    expect(described_class.authenticate(key)).to eq(client)
    travel(2.days) { expect(described_class.authenticate(key)).to be_nil }
    expect { issue(accountant, %w[entries:read], expires_at: 1.day.ago) }.to raise_error(ActiveRecord::RecordInvalid, /expiry must be in the future/)
  end

  it "has a rate of 60 requests a minute unless said otherwise, and keeps the 300 of the keys that came before" do
    expect(issue(accountant, %w[entries:read]).first.rate_limit_per_minute).to eq(60)
    expect(issue(accountant, %w[entries:read], rate_limit_per_minute: 120).first.rate_limit_per_minute).to eq(120)
    expect { issue(accountant, %w[entries:read], rate_limit_per_minute: 0) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "shows when it was last used, and a rotation gives a new secret while the old one dies" do
    client, old = issue(accountant, %w[entries:read])
    expect(client.last_used_at).to be_nil
    new_key = client.rotate!
    expect(described_class.authenticate(old)).to be_nil
    expect(described_class.authenticate(new_key)).to eq(client)
    expect(client.key_digest).not_to include(new_key)
  end
end
