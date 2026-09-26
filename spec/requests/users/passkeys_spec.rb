require "rails_helper"

RSpec.describe "Users::Passkeys", type: :request do
  let(:user) { create(:user, :accountant) }

  before do
    host! "webauthn.test"
    https!
    create(:user_entity, :accountant, user: user)
    sign_in user
  end

  def register(nickname: "YubiKey")
    get options_passkeys_path
    opts = response.parsed_body
    credential = webauthn_fake_client.create(challenge: opts["challenge"], user_verified: true)
    post passkeys_path, params: { credential: credential, nickname: nickname }, as: :json
  end

  it "lists passkeys" do
    get passkeys_path
    expect(response).to have_http_status(:ok)
  end

  it "requires authentication" do
    sign_out user
    get passkeys_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "registers the first passkey and returns recovery codes once" do
    expect { register }.to change { user.webauthn_credentials.count }.by(1)
    expect(response.parsed_body["backup_codes"].size).to eq(10)
  end

  it "does not return recovery codes for later passkeys" do
    register
    register(nickname: "Phone")
    expect(response.parsed_body["backup_codes"]).to be_nil
  end

  it "requires a nickname" do
    register(nickname: " ")
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.webauthn_credentials).to be_empty
  end

  it "rejects a credential answering another challenge" do
    get options_passkeys_path
    credential = webauthn_fake_client.create(challenge: WebAuthn.generate_user_id, user_verified: true)
    post passkeys_path, params: { credential: credential, nickname: "x" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "removes a passkey" do
    credential = create_webauthn_credential_for(user)
    delete passkey_path(credential)
    expect(response).to redirect_to(passkeys_path)
    expect(user.webauthn_credentials.reload).to be_empty
  end
end
