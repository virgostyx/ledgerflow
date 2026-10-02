require "rails_helper"

RSpec.describe "Users::PasskeySessions", type: :request do
  let(:user) { create(:user, :accountant) }
  let!(:stored) { create_webauthn_credential_for(user) }

  before do
    host! "webauthn.test"
    https!
    create(:user_entity, :accountant, user: user)
  end

  def assertion(challenge:, user_handle: Base64.urlsafe_decode64(user.webauthn_id))
    webauthn_fake_client.get(challenge: challenge, user_verified: true, user_handle: user_handle)
  end

  def sign_in_with_passkey(**opts)
    get passkey_session_options_path
    challenge = response.parsed_body["challenge"]
    post passkey_session_path, params: { credential: assertion(challenge: challenge, **opts) }, as: :json
  end

  it "signs the user in and returns the dashboard path" do
    sign_in_with_passkey
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["redirect_to"]).to eq(accounting_root_path)
    expect(stored.reload.last_used_at).to be_present
    get accounting_root_path
    expect(response).not_to redirect_to(new_user_session_path)
  end

  it "rejects an unknown credential" do
    stored.destroy
    sign_in_with_passkey
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects a mismatching user handle" do
    sign_in_with_passkey(user_handle: SecureRandom.random_bytes(64))
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects an inactive user" do
    user.update!(active: false)
    sign_in_with_passkey
    expect(response).to have_http_status(:unprocessable_content)
    get accounting_root_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "rejects a wrong challenge" do
    get passkey_session_options_path
    post passkey_session_path, params: { credential: assertion(challenge: WebAuthn.generate_user_id) }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  describe "second factor (F01)" do
    around do |example|
      previous = Rails.configuration.x.second_factor_required
      Rails.configuration.x.second_factor_required = true
      example.run
    ensure
      Rails.configuration.x.second_factor_required = previous
    end

    before do
      secret = user.begin_totp_enrollment!
      user.confirm_totp!(Totp.code(secret))
    end

    it "counts as the second factor: someone with an authenticator is not asked for a code after a passkey" do
      sign_in_with_passkey

      get accounting_journal_entries_path

      expect(response).not_to redirect_to(two_factor_challenge_path)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "audit trail (F01)" do
    def audit(action) = Accounting::AuditLog.where(action: action, auditable_id: user.id)

    it "records a passkey sign-in" do
      sign_in_with_passkey

      expect(audit("login").count).to eq(1)
      expect(audit("login").first.payload).to include("method" => "passkey")
    end

    it "records a failed passkey attempt of a known user" do
      sign_in_with_passkey(user_handle: SecureRandom.random_bytes(64))

      expect(audit("login_failed").first.payload).to include("method" => "passkey")
    end
  end
end

RSpec.describe "Users::RecoveryCodeSessions", type: :request do
  let(:user) { create(:user, :accountant) }
  let!(:codes) { create_webauthn_credential_for(user) && user.generate_recovery_codes! }

  before { host! "webauthn.test"; https! }

  it "renders the form" do
    get new_recovery_code_session_path
    expect(response).to have_http_status(:ok)
  end

  it "signs in a passwordless user with a valid code, once" do
    post recovery_code_session_path, params: { email: user.email, recovery_code: codes.first }
    expect(response).to redirect_to(passkeys_path)
    delete destroy_user_session_path
    post recovery_code_session_path, params: { email: user.email, recovery_code: codes.first }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "refuses a user who is not passwordless" do
    user.webauthn_credentials.destroy_all
    post recovery_code_session_path, params: { email: user.email, recovery_code: codes.first }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "refuses an inactive user" do
    user.update!(active: false)
    post recovery_code_session_path, params: { email: user.email, recovery_code: codes.first }
    expect(response).to have_http_status(:unprocessable_content)
  end

  describe "second factor (F01)" do
    around do |example|
      previous = Rails.configuration.x.second_factor_required
      Rails.configuration.x.second_factor_required = true
      example.run
    ensure
      Rails.configuration.x.second_factor_required = previous
    end

    it "is not a second factor: someone with an authenticator is still challenged after a recovery code" do
      create(:user_entity, :accountant, user: user)
      secret = user.begin_totp_enrollment!
      user.confirm_totp!(Totp.code(secret, Time.current - 30))
      post recovery_code_session_path, params: { email: user.email, recovery_code: codes.first }

      get accounting_journal_entries_path

      expect(response).to redirect_to(two_factor_challenge_path)
    end
  end

  describe "audit trail (F01)" do
    before { create(:user_entity, :accountant, user: user) }

    def audit(action) = Accounting::AuditLog.where(action: action, auditable_id: user.id)

    it "records a sign-in with a recovery code" do
      post recovery_code_session_path, params: { email: user.email, recovery_code: codes.first }

      expect(audit("login").first.payload).to include("method" => "recovery_code")
    end

    it "records a wrong recovery code of a known user" do
      post recovery_code_session_path, params: { email: user.email, recovery_code: "nope" }

      expect(audit("login_failed").first.payload).to include("method" => "recovery_code")
    end
  end
end

RSpec.describe "Password sign-in for a passwordless user", type: :request do
  it "is refused" do
    host! "webauthn.test"
    https!
    user = create(:user, :accountant, password: "Password123!")
    create(:user_entity, :accountant, user: user)
    create_webauthn_credential_for(user)
    post user_session_path, params: { user: { email: user.email, password: "Password123!" } }
    expect(response).to have_http_status(:unprocessable_content)
    get accounting_root_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
