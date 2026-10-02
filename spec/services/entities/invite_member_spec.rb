require "rails_helper"

RSpec.describe Entities::InviteMember do
  include_context "with entity"

  let(:inviter) { create(:user) }
  let(:attrs)   { { email: "new.person@example.com", full_name: "New Person", role: "accountant" } }

  def invite(**over) = described_class.call(entity: entity, invited_by: inviter, **attrs, **over)

  context "with an email nobody has used yet" do
    it "creates the account and the membership, and mails the link to set a password" do
      result = nil
      expect { result = invite }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(result).to be_success
      user = User.find_by!(email: "new.person@example.com")
      expect(user.full_name).to eq("New Person")
      expect(UserEntity.find_by(user: user, entity: entity)).to be_accountant
      expect(ActionMailer::Base.deliveries.last.to).to eq([ "new.person@example.com" ])
    end

    it "lets the new person sign in only after choosing a password (the random one is never known)" do
      invite

      expect(User.find_by!(email: "new.person@example.com").reset_password_token).to be_present
    end
  end

  context "with an existing account" do
    let!(:existing) { create(:user, email: "new.person@example.com") }

    it "just gives it access, without mail and without touching the account" do
      expect { invite }.not_to change { ActionMailer::Base.deliveries.size }

      expect(UserEntity.find_by(user: existing, entity: entity)).to be_accountant
      expect(User.where(email: "new.person@example.com").count).to eq(1)
    end

    it "can give a limited access (valid until)" do
      invite(valid_until: Date.current + 30)

      expect(UserEntity.find_by(user: existing, entity: entity).valid_until).to eq(Date.current + 30)
    end

    it "refuses someone who already has an access, whatever its state" do
      create(:user_entity, :manager, user: existing, entity: entity, active: false)

      expect(invite).to be_failure
      expect(UserEntity.where(user: existing, entity: entity).count).to eq(1)
    end
  end

  it "refuses an unknown role" do
    expect(invite(role: "superuser")).to be_failure
    expect(User.find_by(email: "new.person@example.com")).to be_nil
  end

  it "refuses a malformed email" do
    expect(invite(email: "not-an-email")).to be_failure
  end

  it "audits the new access in the entity's trail" do
    invite

    row = Accounting::AuditLog.where(auditable_type: "UserEntity", action: "create", entity_id: entity.id).last
    expect(row.payload["changes"]).to include("role")
  end
end
