require "rails_helper"

RSpec.describe User, "passkeys", type: :model do
  let(:user) { create(:user) }

  it "generates a stable webauthn_id lazily" do
    id = user.webauthn_id
    expect(id).to be_present
    expect(user.reload.webauthn_id).to eq(id)
  end

  it "is passwordless only while it has a passkey" do
    expect(user).not_to be_passwordless
    credential = create_webauthn_credential_for(user)
    expect(user.reload).to be_passwordless
    credential.destroy
    expect(user.reload).not_to be_passwordless
  end

  describe "recovery codes" do
    it "generates 10 plain codes and stores only digests" do
      codes = user.generate_recovery_codes!
      expect(codes.size).to eq(10)
      expect(user.recovery_codes.pluck(:code_digest)).not_to include(*codes)
    end

    it "replaces the previous codes when regenerated" do
      user.generate_recovery_codes!
      user.generate_recovery_codes!
      expect(user.recovery_codes.count).to eq(10)
    end

    it "accepts a code once only" do
      code = user.generate_recovery_codes!.first
      expect(user.use_recovery_code!(code)).to be true
      expect(user.use_recovery_code!(code)).to be false
    end

    it "rejects an unknown code" do
      user.generate_recovery_codes!
      expect(user.use_recovery_code!("nope")).to be false
    end
  end
end
