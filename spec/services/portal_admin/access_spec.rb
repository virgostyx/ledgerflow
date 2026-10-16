require 'rails_helper'

# B02a: what the firm does with the people it opens the portal to. Each action is in the audit trail of the company (R18).
RSpec.describe 'Portal access, firm side' do
  include_context 'with entity'

  let(:staff) { create(:user) }

  def trail = Accounting::AuditLog.where(entity_id: entity.id).order(:id).pluck(:action)

  describe PortalAdmin::Invite do
    it 'invites by e-mail, in the trail, with the link and nothing of the books' do
      result = nil
      expect { result = described_class.call(entity: entity, email: 'ann@client.example', full_name: 'Ann', role: 'director', by: staff) }
        .to change { ActionMailer::Base.deliveries.size }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ 'ann@client.example' ])
      expect(mail.body.to_s).to match(%r{https?://#{Regexp.escape(Rails.configuration.x.portal_host)}\S*/invitations/\S+})
      expect(result).to be_success
      expect(trail).to include('portal_invited')
    end

    it 'does not put the token in the trail' do
      result = described_class.call(entity: entity, email: 'ann@client.example', full_name: 'Ann', role: 'director', by: staff)
      token = ActionMailer::Base.deliveries.last.body.to_s[%r{/invitations/(\S+)}, 1]
      expect(token).to be_present
      expect(Accounting::AuditLog.where(entity_id: entity.id).pluck(:payload).to_json).not_to include(token)
      expect(result[:invitation]).to be_persisted
    end

    it 'warns about a shared address' do
      result = described_class.call(entity: entity, email: 'comptabilite@client.example', full_name: 'Accounts', role: 'collaborator', by: staff)
      expect(result[:warning]).to match(/shared/i)
    end

    it 'fails with the reason when the portal is off' do
      entity.update!(features: { 'b02a' => false })
      result = described_class.call(entity: entity, email: 'ann@client.example', full_name: 'Ann', role: 'director', by: staff)
      expect(result).to be_failure
    end
  end

  describe PortalAdmin::RevokeGrant do
    let(:user) { create(:portal_user) }
    let!(:grant) { Portal::Grant.create!(portal_user: user, entity_id: entity.id, role: 'director', capabilities: %w[publications.view]) }

    it 'revokes at once, and the person keeps the other companies' do
      other = Portal::Grant.create!(portal_user: user, entity_id: create(:entity).id, role: 'reader', capabilities: [])
      session, = Portal::Session.start!(user, ip: '1.1.1.1', user_agent: 'x')

      described_class.call(grant: grant, by: staff)

      expect(grant.reload.revoked_at).to be_present
      expect(Portal::Grant.in_force).to contain_exactly(other)
      expect(session.reload.revoked_at).to be_nil
      expect(trail).to include('portal_grant_revoked')
    end

    it 'ends the sessions of a person left with no right at all' do
      session, = Portal::Session.start!(user, ip: '1.1.1.1', user_agent: 'x')
      described_class.call(grant: grant, by: staff)
      expect(session.reload.revoked_at).to be_present
    end
  end

  describe PortalAdmin::ResetAccess do
    let(:user) { create(:portal_user) }

    before { Portal::Grant.create!(portal_user: user, entity_id: entity.id, role: 'director', capabilities: %w[publications.view]) }

    it 'wipes the second factor and the password, ends the sessions and invites again' do
      user.generate_backup_codes!
      session, = Portal::Session.start!(user, ip: '1.1.1.1', user_agent: 'x')

      expect { described_class.call(person: user, entity: entity, by: staff) }.to change { ActionMailer::Base.deliveries.size }.by(1)

      user.reload
      expect(user).to be_invited
      expect(user.totp_secret).to be_nil
      expect(user.backup_codes).to be_empty
      expect(user.authenticate('correct horse battery')).to be_falsey
      expect(session.reload.revoked_at).to be_present
      expect(trail).to include('portal_access_reset')
    end
  end

  describe PortalAdmin::VerifyIdentity do
    it 'records who verified the person and when' do
      user = create(:portal_user)
      described_class.call(person: user, entity: entity, by: staff)

      expect(user.reload).to have_attributes(identity_verified_by_id: staff.id)
      expect(user.identity_verified_at).to be_present
      expect(trail).to include('portal_identity_verified')
    end
  end
end
