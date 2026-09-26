require "rails_helper"

RSpec.describe WebauthnCredential, type: :model do
  subject { create_webauthn_credential_for(create(:user)) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:external_id) }
  it { is_expected.to validate_presence_of(:public_key) }
  it { is_expected.to validate_presence_of(:nickname) }
  it { is_expected.to validate_uniqueness_of(:external_id) }
  it { is_expected.to validate_uniqueness_of(:nickname).scoped_to(:user_id) }
end
