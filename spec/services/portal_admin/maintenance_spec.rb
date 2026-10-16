require 'rails_helper'

# B02a: the journal of the portal copied into the audit trail of the companies (R18), the quarterly review of the accesses, and the suspension of those who no longer come.
RSpec.describe 'Portal maintenance' do
  include_context 'with entity'

  let(:staff)  { create(:user) }
  let(:person) { create(:portal_user) }

  def grant_to(user, capabilities: %w[publications.view], company: entity)
    Portal::Grant.create!(portal_user: user, entity_id: company.id, role: 'director', capabilities: capabilities)
  end

  def trail(action = nil)
    scope = Accounting::AuditLog.where(entity_id: entity.id, actor_type: 'portal_user')
    action ? scope.where(action: action) : scope
  end

  describe PortalAdmin::MirrorEvents do
    it 'copies an event of a company into its trail with the kind of actor, once' do
      Portal::Event.record!('publication_downloaded', user: person, entity_id: entity.id, target_token: 'abc')

      described_class.call
      described_class.call

      row = trail('portal_publication_downloaded').sole
      expect(row.payload).to include('portal_user_id' => person.id, 'email' => person.email, 'target' => 'abc')
      expect(Portal::Event.where(mirrored_at: nil)).to be_empty
    end

    it 'copies an event with no company into the trail of each company of the person' do
      other = create(:entity)
      grant_to(person)
      grant_to(person, company: other)
      Portal::Event.record!('sign_in', user: person)

      described_class.call

      expect(ActsAsTenant.without_tenant { Accounting::AuditLog.where(action: 'portal_sign_in', entity_id: [ entity.id, other.id ]).count }).to eq(2)
    end

    it 'keeps the chain of the trail intact' do
      3.times { Portal::Event.record!('publication_viewed', user: person, entity_id: entity.id, target_token: 'x') }
      described_class.call
      expect(Accounting::AuditVerifier.call(entity: entity)).to be_intact
    end

    it 'marks as done an event that no company can claim (an unknown address), so that it is not tried again' do
      Portal::Event.record!('sign_in_failed', email_tried: 'nobody@x.example')
      described_class.call
      expect(Portal::Event.where(mirrored_at: nil)).to be_empty
    end

    it 'leaves the events of a company where the portal was turned off for later' do
      entity.update!(features: { 'b02a' => false })
      Portal::Event.record!('publication_viewed', user: person, entity_id: entity.id, target_token: 'x')
      described_class.call
      expect(trail('portal_publication_viewed')).to be_empty
    end
  end

  describe PortalAdmin::AccessReview do
    it 'flags the rights that were not used for 90 days, and those that never were' do
      active = create(:portal_user, last_seen_at: 1.day.ago)
      dormant = create(:portal_user, last_seen_at: 100.days.ago)
      never = create(:portal_user, last_seen_at: nil)
      [ active, dormant, never ].each { |u| grant_to(u) }
      never.grants.first.update_columns(created_at: 100.days.ago)

      rows = described_class.call(entity: entity)

      expect(rows.to_h { |r| [ r.portal_user.id, r.inactive ] }).to eq(active.id => false, dormant.id => true, never.id => true)
    end

    it 'does not flag a right that was just given and not yet used' do
      fresh = create(:portal_user, last_seen_at: nil)
      grant_to(fresh)
      expect(described_class.call(entity: entity).sole.inactive).to be(false)
    end
  end

  describe PortalAdmin::SuspendDormant do
    it 'suspends the active people who did not sign in for 180 days, with their sessions, and tells the trail' do
      gone = create(:portal_user, last_sign_in_at: 200.days.ago)
      here = create(:portal_user, last_sign_in_at: 2.days.ago)
      [ gone, here ].each { |u| grant_to(u) }
      session, = Portal::Session.start!(gone, ip: '1.1.1.1', user_agent: 'x')

      described_class.call

      expect(gone.reload).to be_suspended
      expect(here.reload).to be_active
      expect(session.reload.revoked_at).to be_present
      expect(Accounting::AuditLog.where(entity_id: entity.id, action: 'portal_user_suspended_dormant')).to exist
    end

    it 'counts from the creation of the account for someone who never signed in' do
      never = create(:portal_user, last_sign_in_at: nil, created_at: 200.days.ago)
      grant_to(never)
      described_class.call
      expect(never.reload).to be_suspended
    end

    it 'can be reinstated by the firm' do
      gone = create(:portal_user, status: 'suspended')
      grant_to(gone)
      PortalAdmin::Reinstate.call(person: gone, entity: entity, by: staff)
      expect(gone.reload).to be_active
      expect(Accounting::AuditLog.where(entity_id: entity.id, action: 'portal_user_reinstated')).to exist
    end
  end
end

RSpec.describe PortalAdminJob do
  it 'is scheduled: the mirror every minute, the dormant check every night' do
    schedule = YAML.load_file(Rails.root.join('config/recurring.yml')).fetch('production')
    expect(schedule.fetch('portal_mirror_events')).to include('class' => 'PortalAdminJob', 'args' => [ 'mirror' ])
    expect(schedule.fetch('portal_suspend_dormant')).to include('class' => 'PortalAdminJob', 'args' => [ 'dormant' ])
    expect(schedule.fetch('portal_receive_uploads')).to include('class' => 'PortalAdminJob', 'args' => [ 'uploads' ], 'schedule' => 'every minute') # B02b
    expect(schedule.fetch('portal_weekly_summary')).to include('class' => 'PortalAdminJob', 'args' => [ 'weekly' ])
    expect(schedule.fetch('portal_snapshots')).to include('class' => 'PortalAdminJob', 'args' => [ 'snapshots' ])
    expect(schedule.fetch('portal_remind_document_requests')).to include('class' => 'PortalAdminJob', 'args' => [ 'reminders' ])
  end

  it 'runs the task it is given' do
    expect(PortalAdmin::SuspendDormant).to receive(:call)
    described_class.perform_now('dormant')
    expect(PortalAdmin::MirrorEvents).to receive(:call)
    described_class.perform_now

    expect(PortalAdmin::ReceiveUploads).to receive(:call)
    expect(PortalAdmin::SyncUploadProgress).to receive(:call)
    expect(PortalAdmin::SyncDocumentRequests).to receive(:call)
    expect(PortalAdmin::SyncAnswers).to receive(:call)
    expect(PortalAdmin::SealApprovals).to receive(:call)
    expect(PortalAdmin::ApprovalAlerts).to receive(:call)
    expect(PortalAdmin::CheckPublicationCertificates).to receive(:call)
    described_class.perform_now('uploads')
    expect(PortalAdmin::WeeklySummary).to receive(:call)
    described_class.perform_now('weekly')
    expect(PortalAdmin::RemindDocumentRequests).to receive(:call)
    described_class.perform_now('reminders')
  end
end
