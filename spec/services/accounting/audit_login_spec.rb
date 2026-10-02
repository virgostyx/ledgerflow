require "rails_helper"

# F01: sign-ins and failed sign-ins are part of every entity's audit trail the user can work in.
RSpec.describe Accounting::AuditLogin do
  let(:user) { create(:user) }
  let(:entity_a) { create(:entity) }
  let(:entity_b) { create(:entity) }

  def rows(action) = Accounting::AuditLog.where(action: action, auditable_id: user.id)

  it "writes one entry per entity the user can currently work in" do
    create(:user_entity, :accountant, user: user, entity: entity_a)
    create(:user_entity, :auditor, user: user, entity: entity_b)

    described_class.call(user: user, action: "login", method: "password")

    expect(rows("login").pluck(:entity_id)).to contain_exactly(entity_a.id, entity_b.id)
  end

  it "skips an expired or deactivated access" do
    create(:user_entity, :accountant, user: user, entity: entity_a)
    create(:user_entity, :accountant, user: user, entity: entity_b, valid_until: Date.current - 1)

    described_class.call(user: user, action: "login", method: "password")

    expect(rows("login").pluck(:entity_id)).to eq([ entity_a.id ])
  end

  it "keeps who, how and the extra details in the entry" do
    create(:user_entity, :accountant, user: user, entity: entity_a)

    described_class.call(user: user, action: "login_failed", method: "password", failed_attempts: 3, locked: false)

    row = rows("login_failed").first
    expect(row.user_email).to eq(user.email)
    expect(row.payload).to include("method" => "password", "failed_attempts" => 3, "locked" => false)
  end

  it "writes nothing for a user who works in no entity" do
    expect { described_class.call(user: user, action: "login", method: "password") }.not_to change(Accounting::AuditLog, :count)
  end

  it "keeps the audit chain of each entity intact" do
    create(:user_entity, :accountant, user: user, entity: entity_a)
    described_class.call(user: user, action: "login", method: "password")

    expect(Accounting::AuditVerifier.call(entity: entity_a)).to be_intact
  end
end
