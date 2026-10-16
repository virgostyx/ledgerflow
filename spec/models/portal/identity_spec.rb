require 'rails_helper'

# B02a: who the people from outside are, how they get in (an invitation used once, a password, a second factor) and how long a session lives.
RSpec.describe 'Portal identity' do
  let(:entity) { create(:entity) }
  let(:staff)  { create(:user) }

  describe PortalUser do
    it 'is not a User and has a unique email whatever the case' do
      create(:portal_user, email: 'Ann@client.example')
      expect(build(:portal_user, email: 'ann@CLIENT.example')).not_to be_valid
      expect(described_class.new.respond_to?(:role)).to be(false)
    end

    it 'wants a password of 12 characters or more' do
      expect(build(:portal_user, password: 'short')).not_to be_valid
      expect(build(:portal_user, password: 'a long enough one')).to be_valid
    end

    it 'keeps the secret of the second factor encrypted' do
      user = create(:portal_user)
      raw = described_class.connection.select_value("SELECT totp_secret FROM portal_users WHERE id = #{user.id}")
      expect(raw).not_to eq(user.totp_secret)
    end

    it 'locks after five failed attempts and says so' do
      user = create(:portal_user)
      4.times { user.register_failure! }
      expect(user).not_to be_locked
      user.register_failure!
      expect(user).to be_locked
    end

    it 'unlocks by itself after half an hour, and by the firm at once' do
      user = create(:portal_user)
      5.times { user.register_failure! }
      travel_to(31.minutes.from_now) { expect(user).not_to be_locked }
      user.unlock!
      expect(user.reload).not_to be_locked
      expect(user.failed_attempts).to eq(0)
    end

    it 'accepts a code of the app once only' do
      user = create(:portal_user)
      code = Totp.code(user.totp_secret)
      expect(user.verify_totp!(code)).to be(true)
      expect(user.verify_totp!(code)).to be(false)
    end

    it 'gives backup codes, shown once, each usable once' do
      user = create(:portal_user)
      codes = user.generate_backup_codes!
      expect(codes.size).to eq(10)
      expect(user.use_backup_code!(codes.first)).to be_truthy
      expect(user.use_backup_code!(codes.first)).to be_falsey
      expect(user.backup_codes.pluck(:code_digest)).not_to include(codes.first)
    end

    it 'has a second factor once the app was confirmed' do
      expect(build(:portal_user, totp_enabled_at: nil)).not_to be_second_factor_configured
      expect(build(:portal_user)).to be_second_factor_configured
    end
  end

  describe Portal::Invitation do
    def invite(**args)
      Portal::Invitation.issue!(entity: entity, email: 'new@client.example', full_name: 'New Person', role: 'director', capabilities: %w[publications.view], by: staff, **args)
    end

    it 'gives the token once and keeps only its digest' do
      invitation, token = invite

      expect(token.length).to be >= 32
      expect(invitation.token_digest).to eq(Digest::SHA256.hexdigest(token))
      expect(Portal::Invitation.connection.select_values('SELECT token_digest FROM portal_invitations')).not_to include(token)
    end

    it 'creates the person as invited, with no right yet' do
      invitation, = invite

      expect(invitation.portal_user).to be_invited
      expect(invitation.portal_user.grants).to be_empty
    end

    it 'reuses the person of the same email for a second company, without mixing the rights' do
      first, = invite
      second, = invite(entity: create(:entity))

      expect(second.portal_user).to eq(first.portal_user)
    end

    it 'is found by its token while it is valid' do
      invitation, token = invite
      expect(Portal::Invitation.find_usable(token)).to eq(invitation)
      expect(Portal::Invitation.find_usable('nonsense')).to be_nil
    end

    it 'lasts seven days' do
      _, token = invite
      travel_to(6.days.from_now) { expect(Portal::Invitation.find_usable(token)).to be_present }
      travel_to(8.days.from_now) { expect(Portal::Invitation.find_usable(token)).to be_nil }
    end

    it 'is used once' do
      invitation, token = invite
      invitation.accept!
      expect(Portal::Invitation.find_usable(token)).to be_nil
    end

    it 'accepting writes the grant of the invitation' do
      invitation, = invite
      invitation.accept!

      grant = invitation.portal_user.grants.sole
      expect(grant).to have_attributes(entity_id: entity.id, role: 'director', capabilities: %w[publications.view])
    end

    it 'refuses a role it does not know' do
      expect { invite(role: 'owner') }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'refuses a company where the portal is off' do
      entity.update!(features: { 'b02a' => false })
      expect { invite }.to raise_error(ActiveRecord::RecordInvalid, /portal/i)
    end
  end

  describe Portal::Session do
    let(:user) { create(:portal_user) }

    it 'is found by its token, which is stored as a digest' do
      session, token = Portal::Session.start!(user, ip: '1.2.3.4', user_agent: 'x')

      expect(Portal::Session.authenticate(token)).to eq(session)
      expect(session.token_digest).not_to eq(token)
    end

    it 'ends after 30 minutes without a request' do
      _, token = Portal::Session.start!(user, ip: '1.2.3.4', user_agent: 'x')
      travel_to(29.minutes.from_now) { expect(Portal::Session.authenticate(token)).to be_present }
      travel_to(60.minutes.from_now) { expect(Portal::Session.authenticate(token)).to be_nil }
    end

    it 'ends after 12 hours however busy it is' do
      _, token = Portal::Session.start!(user, ip: '1.2.3.4', user_agent: 'x')
      (1..12).each { |h| travel_to(h.hours.from_now - 1.minute) { Portal::Session.authenticate(token) } }
      travel_to(12.hours.from_now + 1.minute) { expect(Portal::Session.authenticate(token)).to be_nil }
    end

    it 'ends when the person is suspended or revoked, at the next request' do
      _, token = Portal::Session.start!(user, ip: '1.2.3.4', user_agent: 'x')
      user.update!(status: 'suspended')
      expect(Portal::Session.authenticate(token)).to be_nil
    end

    it 'can be revoked, one or all of a person' do
      session, token = Portal::Session.start!(user, ip: '1.2.3.4', user_agent: 'x')
      other, other_token = Portal::Session.start!(user, ip: '1.2.3.5', user_agent: 'y')
      session.revoke!
      expect(Portal::Session.authenticate(token)).to be_nil
      expect(Portal::Session.authenticate(other_token)).to eq(other)
      Portal::Session.revoke_all!(user)
      expect(Portal::Session.authenticate(other_token)).to be_nil
    end

    it 'remembers the second factor and how recent it is' do
      session, = Portal::Session.start!(user, ip: '1.2.3.4', user_agent: 'x')
      expect(session).not_to be_second_factor_recent
      session.passed_second_factor!
      expect(session).to be_second_factor_recent
      travel_to(6.minutes.from_now) { expect(session).not_to be_second_factor_recent }
    end
  end
end
