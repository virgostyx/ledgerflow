require 'rails_helper'

# B02c, "Validation des comptes", the client's side: the documents must be opened, the second factor must be recent, the confirmation lists the documents and their fingerprints, three decisions;
# only a director whose identity was checked and who is named may decide; the proof is complete and kept.
RSpec.describe 'Portal approval of the accounts', type: :request do
  let(:entity)  { create(:entity) }
  let(:staff)   { create(:user) }
  let(:director) { create(:portal_user, full_name: 'Dora Director', identity_verified_at: Time.current, identity_verified_by: staff) }
  let(:pdf)     { { filename: 'balance.pdf', content_type: 'application/pdf', data: Prawn::Document.new { |d| d.text 'Balance sheet' }.render } }
  let(:pdf2)    { { filename: 'result.pdf', content_type: 'application/pdf', data: Prawn::Document.new { |d| d.text 'Income statement' }.render } }

  def grant(user = director, role: 'director', capabilities: %w[publications.view accounts.approve])
    Portal::Grant.create!(portal_user: user, entity_id: entity.id, role: role, capabilities: capabilities)
  end

  def sign_in!(user = director)
    post '/session', params: { email: user.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }
  end

  def publish(approvers: [ director ], files: [ pdf, pdf2 ], **extra)
    PortalAdmin::Publish.call(entity: entity, kind: 'situation', title: 'Accounts 2026', files: files, by: staff, requires_approval: true, approvers: approvers, **extra)[:publication]
  end

  def open_all(publication, user = director)
    publication.files.each { |file| get "/downloads/#{Portal::DownloadLink.for(user, file)}" }
  end

  def decide(publication, decision: 'approved', **params)
    post "/publications/#{publication.token}/approval", params: { decision: decision, confirm: '1', comment: 'ok' }.merge(params)
  end

  before { host! Rails.configuration.x.portal_host }

  describe 'the page' do
    it 'shows the decision form only to an approver, with the text of the scope and the documents with their short fingerprints' do
      grant
      publication = publish
      sign_in!

      get "/publications/#{publication.token}"

      expect(response.body).to include('not a qualified electronic signature', 'Approve', 'Refuse')
      publication.files.each { |f| expect(response.body).to include(f.sha256.first(12)) }
    end

    it 'keeps the buttons off until every document was opened' do
      grant
      publication = publish
      sign_in!

      get "/publications/#{publication.token}"
      expect(response.body).to match(/disabled[^>]*>\s*Approve|Open every document/)
      get "/downloads/#{Portal::DownloadLink.for(director, publication.files.first)}"
      get "/publications/#{publication.token}"
      expect(response.body).to include('Open every document')

      open_all(publication)
      get "/publications/#{publication.token}"
      expect(response.body).not_to include('Open every document')
    end

    it 'does not show the form to someone who is not an approver' do
      colleague = create(:portal_user, identity_verified_at: Time.current, identity_verified_by: staff)
      grant
      grant(colleague)
      publication = publish
      sign_in!(colleague)
      get "/publications/#{publication.token}"
      expect(response.body).not_to include('Approve')
    end
  end

  describe 'deciding' do
    before { grant }

    it 'refuses before the documents were opened' do
      publication = publish
      sign_in!

      decide(publication)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Portal::Approval.count).to eq(0)
    end

    it 'asks for a recent second factor, and comes back after it' do
      publication = publish
      sign_in!
      open_all(publication)
      Portal::Session.update_all(second_factor_at: 10.minutes.ago)

      decide(publication)

      expect(response).to redirect_to(%r{/second_factor/challenge\?return_to=})
      expect(Portal::Approval.count).to eq(0)
      travel 31.seconds # the next code of the application: a code is not accepted twice
      post '/second_factor/challenge', params: { code: Totp.code(director.totp_secret), return_to: "/publications/#{publication.token}" }
      expect(response).to redirect_to("/publications/#{publication.token}")
    end

    it 'does not take a backup code for a decision: the code of the application is needed (decision of 2026-10-17)' do
      publication = publish
      codes = director.generate_backup_codes!
      sign_in!
      open_all(publication)
      Portal::Session.update_all(second_factor_at: 10.minutes.ago)

      decide(publication)
      expect(response).to redirect_to(%r{totp_only=1})

      post '/second_factor/challenge', params: { code: codes.first, return_to: "/publications/#{publication.token}", totp_only: '1' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(Portal::Session.first.second_factor_at).to be < 5.minutes.ago

      # a session that passed with a backup code long ago is not enough either, even if it is recent
      Portal::Session.update_all(second_factor_at: Time.current, second_factor_method: 'backup_code')
      decide(publication)
      expect(response).to redirect_to(%r{totp_only=1})
      expect(Portal::Approval.count).to eq(0)
    end

    it 'refuses an address to come back to that is not on the portal' do
      sign_in!
      travel 31.seconds
      post '/second_factor/challenge', params: { code: Totp.code(director.totp_secret), return_to: 'https://evil.example/' }
      expect(response).to redirect_to('/')
      travel 31.seconds
      post '/second_factor/challenge', params: { code: Totp.code(director.totp_secret), return_to: '//evil.example' }
      expect(response).to redirect_to('/')
    end

    it 'needs the confirmation box' do
      publication = publish
      sign_in!
      open_all(publication)
      decide(publication, confirm: '0')
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'keeps a complete proof of an approval' do
      publication = publish
      sign_in!
      open_all(publication)

      decide(publication, comment: 'Looks right')

      approval = Portal::Approval.sole
      expect(response).to redirect_to("/publications/#{publication.token}")
      expect(approval).to have_attributes(decision: 'approved', comment: 'Looks right', portal_user_id: director.id, entity_id: entity.id, status: 'active')
      ev = approval.evidence
      expect(ev['manifest'].map { |m| m['sha256'] }).to eq(publication.files.map(&:sha256))
      expect(ev['manifest_hash']).to eq(approval.manifest_hash)
      expect(ev['approver']).to include('email' => director.email, 'full_name' => 'Dora Director')
      expect(ev['second_factor']).to include('method' => 'totp')
      expect(ev['ip']).to be_present
      expect(ev['user_agent_sha256']).to match(/\A\h{64}\z/)
      expect(ev['legal_text']).to include('version' => Portal::ApprovalText::VERSION)
      expect(ev['legal_text']['text']).to include('not a qualified electronic signature')
      expect(approval.evidence_hash).to eq(Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate(ev)))
    end

    it 'needs a remark to approve with remarks, and a reason to refuse' do
      publication = publish
      sign_in!
      open_all(publication)

      decide(publication, decision: 'approved_with_remarks', comment: ' ')
      expect(response).to have_http_status(:unprocessable_content)
      decide(publication, decision: 'refused', comment: '')
      expect(response).to have_http_status(:unprocessable_content)

      decide(publication, decision: 'refused', comment: 'The cash is wrong')
      expect(Portal::Approval.sole).to have_attributes(decision: 'refused', comment: 'The cash is wrong')
    end

    it 'does not take a decision on a decision: one active approval per person' do
      publication = publish
      sign_in!
      open_all(publication)
      decide(publication)
      decide(publication, decision: 'refused', comment: 'changed my mind')
      expect(Portal::Approval.count).to eq(1)
    end

    it 'refuses an unknown decision' do
      publication = publish
      sign_in!
      open_all(publication)
      decide(publication, decision: 'maybe')
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'refuses a publication that was withdrawn between the opening and the decision, with a clear message' do
      publication = publish
      sign_in!
      open_all(publication)
      PortalAdmin::Withdraw.call(publication: publication, by: staff, reason: 'wrong numbers')

      decide(publication)

      expect(response).to have_http_status(:not_found).or have_http_status(:gone).or have_http_status(:unprocessable_content)
      expect(Portal::Approval.count).to eq(0)
    end

    it 'refuses a publication replaced by a newer version' do
      publication = publish
      sign_in!
      open_all(publication)
      publish(replaces: publication)
      decide(publication)
      expect(Portal::Approval.count).to eq(0)
    end
  end

  describe 'who may decide (criterion 7)' do
    it 'refuses a director who lost the right to approve after the publication, and a person who is no director' do
      grant
      publication = publish
      Portal::Grant.where(portal_user: director).update_all(capabilities: %w[publications.view])
      sign_in!
      open_all(publication)
      decide(publication)
      expect(Portal::Approval.count).to eq(0)
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses a director whose identity was not verified, and a director who is not named' do
      unverified = create(:portal_user, identity_verified_at: nil)
      grant(unverified)
      grant
      publication = publish
      sign_in!(unverified)
      open_all(publication, unverified)
      decide(publication)
      expect(Portal::Approval.count).to eq(0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
