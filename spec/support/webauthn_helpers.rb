require "webauthn/fake_client"

module WebauthnHelpers
  WEBAUTHN_TEST_ORIGIN = "https://webauthn.test".freeze

  def webauthn_fake_client
    @webauthn_fake_client ||= WebAuthn::FakeClient.new(WEBAUTHN_TEST_ORIGIN)
  end

  # Runs a full, real registration ceremony against a user and persists the
  # resulting credential - used to set up "already has a passkey" fixtures
  # without duplicating controller logic.
  def create_webauthn_credential_for(user, nickname: "Test key", user_verified: true, client: webauthn_fake_client)
    creation_options = WebAuthn::Credential.options_for_create(
      user: { id: user.webauthn_id, name: user.email, display_name: user.full_name }
    )

    attestation = client.create(challenge: creation_options.challenge, user_verified: user_verified)
    webauthn_credential = WebAuthn::Credential.from_create(attestation)
    webauthn_credential.verify(creation_options.challenge, user_verification: user_verified)

    user.webauthn_credentials.create!(
      external_id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      nickname: nickname
    )
  end
end

RSpec.configure do |config|
  config.include WebauthnHelpers
end
