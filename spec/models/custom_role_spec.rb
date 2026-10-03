require "rails_helper"

# F01 (spec §4): an owner composes a role from the fine permissions of Permissions::MATRIX.
RSpec.describe CustomRole do
  include_context "with entity"

  def role(**over) = described_class.new({ name: "Payroll clerk", permissions: %w[records.view reports.view] }.merge(over))

  it "is valid with a name and known permissions" do
    expect(role).to be_valid
  end

  it "needs a name, unique in the entity" do
    expect(role(name: " ")).not_to be_valid

    role.save!
    expect(role).not_to be_valid
    ActsAsTenant.with_tenant(create(:entity)) { expect(role).to be_valid }
  end

  it "refuses a permission that does not exist" do
    expect(role(permissions: %w[records.view entries.typo])).not_to be_valid
  end

  it "reserves user administration to the owners" do
    custom = role(permissions: %w[records.view users.manage])

    expect(custom).not_to be_valid
    expect(custom.errors[:permissions].join).to match(/owner/i)
  end

  it "keeps each permission once, without blanks" do
    expect(role(permissions: [ "", "records.view", "records.view" ]).tap(&:save!).permissions).to eq([ "records.view" ])
  end

  it "cannot be deleted while someone holds it" do
    custom = role.tap(&:save!)
    create(:user_entity, :manager, entity: entity, custom_role: custom)

    expect(custom.destroy).to be false
    expect(described_class.count).to eq(1)
  end

  it "can be deleted once nobody holds it" do
    expect(role.tap(&:save!).destroy).to be_truthy
  end

  it "is in the audit trail" do
    custom = role.tap(&:save!)

    expect(Accounting::AuditLog.where(auditable_type: "CustomRole", auditable_id: custom.id, action: "create")).to be_present
  end
end
