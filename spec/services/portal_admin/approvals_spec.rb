require 'rails_helper'

# B02c, "Validation des comptes", the firm's side: the proof is sealed with the signing key of B03c and checks out; altering it breaks it; a new version supersedes the approvals; the status follows the
# policy (one or all), a disagreement waits and alerts the firm; the closing waits for the approval when the company asks for it.
RSpec.describe 'Client approval of the accounts' do
  include_context 'with signing keys directory'

  let(:entity)   { create(:entity) }
  let(:staff)    { create(:user) }
  let(:director) { create(:portal_user, full_name: 'Dora Director', identity_verified_at: Time.current, identity_verified_by: staff) }
  let(:partner)  { create(:portal_user, full_name: 'Paul Partner', identity_verified_at: Time.current, identity_verified_by: staff) }
  let(:pdf)      { { filename: 'balance.pdf', content_type: 'application/pdf', data: Prawn::Document.new { |d| d.text 'Balance sheet' }.render } }

  before do
    [ director, partner ].each { |p| Portal::Grant.create!(portal_user: p, entity_id: entity.id, role: 'director', capabilities: %w[publications.view accounts.approve]) }
    Ledger::SigningKeys.generate!
    ActionMailer::Base.deliveries.clear
  end

  def publish(approvers: [ director ], policy: 'one', **extra)
    PortalAdmin::Publish.call(entity: entity, kind: 'situation', title: 'Accounts 2026', files: [ pdf ], by: staff, requires_approval: true, approvers: approvers, approvals_required: policy, **extra)
  end

  def session_of(person) = Portal::Session.create!(portal_user: person, token_digest: SecureRandom.hex(8), last_seen_at: Time.current, second_factor_at: Time.current, second_factor_method: 'totp')

  def approve!(publication, person: director, decision: 'approved', comment: nil)
    Portal::DocumentView.record!(publication.files.first, person)
    Portal::Approval.record!(publication: publication, person: person, session: session_of(person), decision: decision, comment: comment, ip: '10.0.0.1', user_agent: 'Spec/1.0', locale: 'en')
  end

  describe 'publishing for approval' do
    it 'names the approvers and freezes them with the publication' do
      publication = publish[:publication]
      expect(publication.approvers).to eq([ director ])
      expect(publication.approvals_required).to eq('one')
      expect { publication.approver_rows.first.update!(portal_user: partner) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'refuses an approver who is not a director with a verified identity and the right to approve' do
      unverified = create(:portal_user, identity_verified_at: nil)
      Portal::Grant.create!(portal_user: unverified, entity_id: entity.id, role: 'director', capabilities: %w[accounts.approve])
      collaborator = create(:portal_user, identity_verified_at: Time.current)
      Portal::Grant.create!(portal_user: collaborator, entity_id: entity.id, role: 'collaborator', capabilities: %w[publications.view])

      expect(publish(approvers: [ unverified ])).to be_failure
      expect(publish(approvers: [ collaborator ])).to be_failure
      expect(publish(approvers: [])).to be_failure
      expect(publish(policy: 'most')).to be_failure
      expect(Portal::Publication.count).to eq(0)
    end

    it 'invites to approve again: a new version supersedes the approvals of the former' do
      first = publish[:publication]
      approval = approve!(first)

      second = publish(replaces: first)[:publication]

      expect(approval.reload.status).to eq('superseded')
      expect(PortalAdmin::ApprovalStatus.call(second)[:state]).to eq(:pending)
      expect(PortalAdmin::ApprovalStatus.call(first)[:state]).to eq(:superseded)
    end
  end

  describe PortalAdmin::SealApprovals do
    it 'signs the proof with the key of the instance, and keeps the signature' do
      approval = approve!(publish[:publication])

      described_class.call

      approval.reload
      expect(approval).to be_sealed
      expect(approval.seal_key_id).to eq(Ledger::SigningKey.find_by(status: 'active').key_id)
    end

    it 'seals once, and leaves a proof unsealed when there is no key' do
      approval = approve!(publish[:publication])
      Ledger::SigningKey.update_all(status: 'revoked')

      described_class.call
      expect(approval.reload).not_to be_sealed

      Ledger::SigningKey.update_all(status: 'active')
      described_class.call
      sealed_at = approval.reload.sealed_at
      described_class.call
      expect(approval.reload.sealed_at).to eq(sealed_at)
    end

    it 'cannot change a sealed proof, nor delete it' do
      approval = approve!(publish[:publication])
      described_class.call
      approval.reload

      expect { approval.update!(seal_signature: 'x') }.to raise_error(ActiveRecord::StatementInvalid)
      expect { approval.update!(comment: 'other') }.to raise_error(ActiveRecord::StatementInvalid)
      expect { approval.delete }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe PortalAdmin::VerifyApproval do
    let(:approval) { approve!(publish[:publication]).tap { PortalAdmin::SealApprovals.call }.reload }

    it 'checks out: the hash, the manifest of the files and the signature' do
      result = described_class.call(approval)
      expect(result).to be_valid
      expect(result.problems).to be_empty
    end

    it 'fails when the evidence was altered (criterion 5)' do
      tamper(:portal_approvals) { approval.update_columns(evidence: approval.evidence.merge('decision' => 'refused')) }
      expect(described_class.call(approval.reload)).not_to be_valid
      expect(described_class.call(approval).problems.join).to match(/evidence/)
    end

    it 'fails when the signature was altered' do
      tamper(:portal_approvals) { approval.update_columns(seal_signature: Base64.strict_encode64('x' * 64)) }
      expect(described_class.call(approval.reload).problems.join).to match(/signature/)
    end

    it 'fails when a published file no longer matches the manifest' do
      tamper(:portal_publication_files) { approval.publication.files.first.update_columns(sha256: 'f' * 64) }
      expect(described_class.call(approval.reload).problems.join).to match(/manifest|file/)
    end

    it 'says an unsealed proof is not yet sealed' do
      fresh = approve!(publish[:publication])
      expect(described_class.call(fresh).problems.join).to match(/not sealed/)
    end

    it 'still verifies with a key that was retired since (a key is never deleted)' do
      approval
      Ledger::SigningKeys.rotate!
      expect(described_class.call(approval.reload)).to be_valid
    end
  end

  describe PortalAdmin::ApprovalProofPdf do
    it 'makes the document "proof of approval" with the manifest, the decision, the second factor, the text and how to verify' do
      approval = approve!(publish[:publication], comment: 'All good')
      PortalAdmin::SealApprovals.call

      pdf_text = PDF::Reader.new(StringIO.new(described_class.call(approval.reload))).pages.map(&:text).join(' ')

      expect(pdf_text).to include('Proof of approval', 'Dora Director', 'balance.pdf', approval.evidence_hash.first(16), 'All good', 'not a qualified electronic signature', approval.seal_key_id)
    end
  end

  describe PortalAdmin::ApprovalStatus do
    it 'is approved when one approver approves (policy "one"), also with remarks' do
      publication = publish(approvers: [ director, partner ])[:publication]
      expect(described_class.call(publication)[:state]).to eq(:pending)
      approve!(publication, decision: 'approved_with_remarks', comment: 'one remark')
      expect(described_class.call(publication)[:state]).to eq(:approved)
    end

    it 'needs every approver under the policy "all"' do
      publication = publish(approvers: [ director, partner ], policy: 'all')[:publication]
      approve!(publication)
      expect(described_class.call(publication)).to include(state: :pending, waiting_for: [ partner.id ])
      approve!(publication, person: partner)
      expect(described_class.call(publication)[:state]).to eq(:approved)
    end

    it 'is refused when everyone who decided refused' do
      publication = publish[:publication]
      approve!(publication, decision: 'refused', comment: 'no')
      expect(described_class.call(publication)[:state]).to eq(:refused)
    end

    it 'waits, and alerts the firm, when two directors disagree' do
      publication = publish(approvers: [ director, partner ])[:publication]
      approve!(publication)
      approve!(publication, person: partner, decision: 'refused', comment: 'I disagree')

      expect(described_class.call(publication)[:state]).to eq(:disputed)
      alerts = -> { ActsAsTenant.with_tenant(entity) { Accounting::Notification.where(user: staff, event: 'portal_decision_disputed').count } }
      expect { PortalAdmin::ApprovalAlerts.call }.to change(&alerts).by(1)
      expect { PortalAdmin::ApprovalAlerts.call }.not_to change(&alerts) # once
    end

    it 'does not count an approval of someone who is not an approver any more, and blocks when nobody qualifies' do
      publication = publish[:publication]
      approve!(publication)
      director.update!(identity_verified_at: nil) # replaced: the identity of the new director must be checked

      status = described_class.call(publication)

      expect(status[:state]).to eq(:blocked)
      expect(status[:problem]).to match(/identity/)
    end

    it 'lets a new director take the place, once their identity is verified' do
      publication = publish(approvers: [ director, partner ])[:publication]
      approve!(publication)
      director.grants.update_all(revoked_at: Time.current)
      expect(described_class.call(publication)[:state]).to eq(:pending) # the approval of the former director no longer counts
      approve!(publication, person: partner)
      expect(described_class.call(publication)[:state]).to eq(:approved)
    end

    it 'says "not required" for a publication that asks for nothing' do
      plain = PortalAdmin::Publish.call(entity: entity, kind: 'other', title: 'FYI', files: [ pdf ], by: staff)[:publication]
      expect(described_class.call(plain)[:state]).to eq(:not_required)
    end
  end

  describe 'the firm is told' do
    it 'tells the person who published, when a decision is sealed, with no content' do
      publication = publish[:publication]
      approve!(publication, decision: 'refused', comment: 'secret reason')

      PortalAdmin::SealApprovals.call

      ActsAsTenant.with_tenant(entity) do
        expect(Accounting::Notification.where(user: staff).where("event LIKE 'portal_decision:%'").count).to eq(1)
        expect(Accounting::AuditLog.where(action: 'portal_publication_decided').count).to eq(1)
      end
    end
  end
end
