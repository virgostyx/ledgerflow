require "rails_helper"

# F01: whoever can validate, unlock or administer signs in with a second factor (TOTP); a passkey counts as one.
RSpec.describe "Two-factor authentication", type: :request do
  include_context "with entity"

  let(:password) { "Password123!" }
  let(:owner)    { create(:user, role: :admin, password: password) }
  let!(:owner_membership) { create(:user_entity, :admin, user: owner, entity: entity) }

  around do |example|
    previous = Rails.configuration.x.second_factor_required
    Rails.configuration.x.second_factor_required = true
    example.run
  ensure
    Rails.configuration.x.second_factor_required = previous
  end

  def enroll!(user)
    secret = user.begin_totp_enrollment!
    user.confirm_totp!(Totp.code(secret, Time.current - 30)) # the current code stays unused
    secret
  end

  def sign_in_with_password(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  def audit(action, user) = Accounting::AuditLog.where(action: action, auditable_id: user.id)

  describe "enrolment is required of a role that can validate" do
    before { sign_in owner }

    it "sends the person to set it up before anything else" do
      get accounting_journal_entries_path

      expect(response).to redirect_to(two_factor_path)
      expect(flash[:alert]).to match(/two-factor/i)
    end

    it "shows the key to type and a QR code to scan" do
      get two_factor_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(owner.reload.totp_secret.scan(/.{1,4}/).join(" ")) # shown in groups of four
      expect(response.body).to include("<svg")
    end

    it "keeps the same secret when the page is opened twice" do
      get two_factor_path
      first = owner.reload.totp_secret
      get two_factor_path

      expect(owner.reload.totp_secret).to eq(first)
    end

    it "refuses a wrong code and stays locked out" do
      get two_factor_path

      post two_factor_path, params: { code: "000000" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(owner.reload).not_to be_totp_enabled
      get accounting_journal_entries_path
      expect(response).to redirect_to(two_factor_path)
    end

    it "turns it on with the code the app shows, lets the person in, and audits it" do
      get two_factor_path

      post two_factor_path, params: { code: Totp.code(owner.reload.totp_secret) }

      expect(response).to have_http_status(:ok) # the backup codes are shown once, then the person goes on
      expect(response.body).to include(accounting_root_path)
      expect(owner.reload).to be_totp_enabled
      get accounting_journal_entries_path
      expect(response).to have_http_status(:ok)
      expect(audit("two_factor_enabled", owner).count).to eq(1)
    end
  end

  describe "the challenge at sign-in" do
    let!(:secret) { enroll!(owner) }

    it "is asked after the password, before anything else" do
      sign_in_with_password(owner)

      get accounting_journal_entries_path

      expect(response).to redirect_to(two_factor_challenge_path)
    end

    it "lets the person in with the current code, and back to where they were going" do
      sign_in_with_password(owner)
      get accounting_journal_entries_path

      post two_factor_challenge_path, params: { code: Totp.code(secret) }

      expect(response).to redirect_to(accounting_journal_entries_path)
      get accounting_journal_entries_path
      expect(response).to have_http_status(:ok)
    end

    it "refuses a wrong code, audits the failure and keeps the door shut" do
      sign_in_with_password(owner)

      post two_factor_challenge_path, params: { code: "123456" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(audit("login_failed", owner).last.payload).to include("method" => "totp")
      get accounting_journal_entries_path
      expect(response).to redirect_to(two_factor_challenge_path)
    end

    it "refuses a code that was already used, even from another session" do
      code = Totp.code(secret)
      sign_in_with_password(owner)
      post two_factor_challenge_path, params: { code: code }
      expect(response).to redirect_to(accounting_root_path)

      delete destroy_user_session_path
      sign_in_with_password(owner)
      post two_factor_challenge_path, params: { code: code }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "asks again after signing out and back in" do
      sign_in_with_password(owner)
      post two_factor_challenge_path, params: { code: Totp.code(secret) }
      delete destroy_user_session_path

      sign_in_with_password(owner)
      get accounting_journal_entries_path

      expect(response).to redirect_to(two_factor_challenge_path)
    end

    it "does not let one person's verification serve another's session" do
      other = create(:user, role: :admin, password: password)
      create(:user_entity, :admin, user: other, entity: entity)
      enroll!(other)
      sign_in_with_password(owner)
      post two_factor_challenge_path, params: { code: Totp.code(secret) }
      delete destroy_user_session_path

      sign_in_with_password(other)
      get accounting_journal_entries_path

      expect(response).to redirect_to(two_factor_challenge_path)
    end

    it "is closed when there is nothing to verify (not signed in)" do
      get two_factor_challenge_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "who is not asked" do
    it "does not ask an assistant, who may still enrol voluntarily" do
      assistant = create(:user, role: :auditor)
      create(:user_entity, :assistant, user: assistant, entity: entity)
      sign_in assistant

      get accounting_journal_entries_path
      expect(response).to have_http_status(:ok)

      get two_factor_path
      post two_factor_path, params: { code: Totp.code(assistant.reload.totp_secret) }
      expect(assistant.reload).to be_totp_enabled
    end

    it "challenges a voluntary enrolment too, at the next sign-in" do
      assistant = create(:user, role: :auditor, password: password)
      create(:user_entity, :assistant, user: assistant, entity: entity)
      enroll!(assistant)

      sign_in_with_password(assistant)
      get accounting_journal_entries_path

      expect(response).to redirect_to(two_factor_challenge_path)
    end

    it "does not ask an owner while F01 is off for the entity" do
      entity.update!(features: { "f01" => false })
      sign_in owner

      get accounting_journal_entries_path

      expect(response).to have_http_status(:ok)
    end

    it "does not ask anyone when the setting is off (the test suite's default)" do
      Rails.configuration.x.second_factor_required = false
      sign_in owner

      get accounting_journal_entries_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "switching it off" do
    it "is refused to someone whose role requires it" do
      secret = enroll!(owner)
      sign_in_with_password(owner)
      post two_factor_challenge_path, params: { code: Totp.code(secret) }

      delete two_factor_path, params: { code: Totp.code(secret, Time.current + 30) }

      expect(owner.reload).to be_totp_enabled
      expect(flash[:alert]).to match(/requires two-factor/i)
    end

    it "is possible for a voluntary user with a valid code, and is audited" do
      assistant = create(:user, role: :auditor, password: password)
      create(:user_entity, :assistant, user: assistant, entity: entity)
      secret = enroll!(assistant)
      sign_in_with_password(assistant)
      post two_factor_challenge_path, params: { code: Totp.code(secret) }

      delete two_factor_path, params: { code: Totp.code(secret, Time.current + 30) }

      expect(assistant.reload).not_to be_totp_enabled
      expect(audit("two_factor_disabled", assistant).count).to eq(1)
    end

    it "needs a valid code" do
      assistant = create(:user, role: :auditor, password: password)
      create(:user_entity, :assistant, user: assistant, entity: entity)
      secret = enroll!(assistant)
      sign_in_with_password(assistant)
      post two_factor_challenge_path, params: { code: Totp.code(secret) }

      delete two_factor_path, params: { code: "000000" }

      expect(assistant.reload).to be_totp_enabled
    end
  end

  describe "guessing the code" do
    it "is throttled: five tries per 20 seconds, then 429" do
      Rack::Attack.enabled = true
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      secret = enroll!(owner)
      sign_in_with_password(owner)

      6.times { post two_factor_challenge_path, params: { code: "000000" }, headers: { "REMOTE_ADDR" => "9.9.9.9" } }

      expect(response).to have_http_status(:too_many_requests)
      expect(secret).to be_present
    ensure
      Rack::Attack.enabled = false
    end
  end

  describe "backup codes of the second factor" do
    def codes_in(body) = body.scan(/\b[0-9a-f]{10}\b/).uniq

    it "shows ten one-time codes when the second factor is switched on, and keeps only their digests" do
      sign_in owner
      get two_factor_path

      post two_factor_path, params: { code: Totp.code(owner.reload.totp_secret) }

      codes = codes_in(response.body)
      expect(codes.size).to eq(User::RECOVERY_CODE_COUNT)
      expect(owner.recovery_codes.totp.unused.count).to eq(User::RECOVERY_CODE_COUNT)
      expect(RecoveryCode.pluck(:code_digest).join).not_to include(codes.first)
    end

    context "at the challenge" do
      let!(:secret) { enroll!(owner) }
      let!(:codes)  { owner.generate_totp_backup_codes! }

      it "lets the person in with a backup code, once, and audits it" do
        sign_in_with_password(owner)

        post two_factor_challenge_path, params: { code: codes.first }

        expect(response).to redirect_to(accounting_root_path)
        expect(audit("two_factor_backup_code_used", owner).count).to eq(1)

        delete destroy_user_session_path
        sign_in_with_password(owner)
        post two_factor_challenge_path, params: { code: codes.first }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "refuses a wrong backup code" do
        sign_in_with_password(owner)

        post two_factor_challenge_path, params: { code: "0123456789" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(audit("login_failed", owner).last.payload).to include("method" => "totp")
      end

      it "is not the recovery code of a passkey: the two sets never open each other's door" do
        passwordless = create(:user)
        passkey_codes = passwordless.generate_recovery_codes!

        expect(passwordless.use_recovery_code!(codes.first)).to be false
        expect(owner.use_totp_backup_code!(passkey_codes.first)).to be false
      end
    end

    context "regenerating" do
      let!(:secret) { enroll!(owner) }
      let!(:old)    { owner.generate_totp_backup_codes! }

      before do
        sign_in_with_password(owner)
        post two_factor_challenge_path, params: { code: Totp.code(secret) }
      end

      it "replaces the codes when the person proves it with a current code" do
        post backup_codes_two_factor_path, params: { code: Totp.code(secret, Time.current + 30) }

        fresh = codes_in(response.body)
        expect(fresh.size).to eq(User::RECOVERY_CODE_COUNT)
        expect(owner.use_totp_backup_code!(old.first)).to be false
        expect(owner.use_totp_backup_code!(fresh.first)).to be_truthy
      end

      it "keeps the old codes when the code is wrong" do
        post backup_codes_two_factor_path, params: { code: "000000" }

        expect(owner.use_totp_backup_code!(old.first)).to be_truthy
      end
    end

    it "switching the second factor off takes its backup codes with it" do
      user = create(:user, role: :manager, password: password)
      create(:user_entity, :manager, user: user, entity: entity)
      enroll!(user)
      user.generate_totp_backup_codes!

      user.disable_totp!

      expect(user.recovery_codes.totp.count).to eq(0)
    end
  end
end
