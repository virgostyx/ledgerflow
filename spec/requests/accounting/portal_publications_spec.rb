require "rails_helper"

# B02a, firm side: publishing to the portal, a new version, withdrawing. Right: portal.manage.
RSpec.describe "Portal publications (firm side)", type: :request do
  include_context "with entity"

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:file)       { Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4\nhello\n%%EOF"), "application/pdf", original_filename: "march.pdf") }

  before { sign_in accountant }

  def publish_params(**extra) = { kind: "monthly_report", title: "March 2026", message: "Here it is", files: [ file ] }.merge(extra)

  it "publishes uploaded files" do
    expect { post accounting_portal_publications_path, params: publish_params }.to change { Portal::Publication.count }.by(1)

    publication = Portal::Publication.last
    expect(publication.files.sole.filename).to eq("march.pdf")
    expect(response).to redirect_to(accounting_portal_publications_path)
  end

  it "lists the publications of the company, with their versions and state" do
    publication = PortalAdmin::Publish.call(entity: entity, kind: "other", title: "Listed one", by: accountant, files: [ { filename: "a.pdf", content_type: "application/pdf", data: "%PDF" } ])[:publication]
    PortalAdmin::Publish.call(entity: create(:entity), kind: "other", title: "Foreign", by: accountant, files: [ { filename: "a.pdf", content_type: "application/pdf", data: "%PDF" } ])

    get accounting_portal_publications_path
    expect(response.body).to include("Listed one").and include(publication.files.first.sha256.first(12))
    expect(response.body).not_to include("Foreign")
  end

  it "shows why a publication was refused" do
    post accounting_portal_publications_path, params: publish_params(title: "")
    follow_redirect!
    expect(response.body).to match(/title/i)
    expect(Portal::Publication.count).to eq(0)
  end

  it "publishes a new version that replaces the former" do
    first = PortalAdmin::Publish.call(entity: entity, kind: "other", title: "v1", by: accountant, files: [ { filename: "a.pdf", content_type: "application/pdf", data: "%PDF" } ])[:publication]
    post accounting_portal_publications_path, params: publish_params(replaces: first.token)
    expect(first.reload.replaced_by_id).to eq(Portal::Publication.last.id)
  end

  it "names recipients among the people of the company only" do
    mine = create(:portal_user)
    Portal::Grant.create!(portal_user: mine, entity_id: entity.id, role: "reader", capabilities: %w[publications.view])
    stranger = create(:portal_user)
    post accounting_portal_publications_path, params: publish_params(recipient_ids: [ mine.id, stranger.id ])
    expect(Portal::Publication.last.recipients).to contain_exactly(mine)
  end

  it "withdraws, with a reason" do
    publication = PortalAdmin::Publish.call(entity: entity, kind: "other", title: "v1", by: accountant, files: [ { filename: "a.pdf", content_type: "application/pdf", data: "%PDF" } ])[:publication]
    post withdraw_accounting_portal_publication_path(publication.token), params: { reason: "sent by mistake" }
    expect(publication.reload).to be_withdrawn
  end

  it "does not withdraw a publication of another company" do
    foreign = PortalAdmin::Publish.call(entity: create(:entity), kind: "other", title: "x", by: accountant, files: [ { filename: "a.pdf", content_type: "application/pdf", data: "%PDF" } ])[:publication]
    post withdraw_accounting_portal_publication_path(foreign.token), params: { reason: "x" }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload).to be_published
  end

  it "is closed to those who may not manage the portal" do
    sign_in reader
    post accounting_portal_publications_path, params: publish_params
    expect(Portal::Publication.count).to eq(0)
  end

  describe "approval of the accounts by the client (B02c)" do
    include_context "with signing keys directory"

    let(:director) { create(:portal_user, full_name: "Dora Director", identity_verified_at: Time.current, identity_verified_by: accountant) }
    let(:pdf)      { Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4\nhello\n%%EOF"), "application/pdf", original_filename: "accounts.pdf") }

    before do
      Portal::Grant.create!(portal_user: director, entity_id: entity.id, role: "director", capabilities: %w[publications.view accounts.approve])
      Ledger::SigningKeys.generate!
    end

    def approved_publication
      publication = PortalAdmin::Publish.call(entity: entity, kind: "situation", title: "Accounts 2026", by: accountant, requires_approval: true, approvers: [ director ],
                                              files: [ { filename: "a.pdf", content_type: "application/pdf", data: "%PDF-1.4 x" } ])[:publication]
      session = Portal::Session.create!(portal_user: director, token_digest: SecureRandom.hex(8), last_seen_at: Time.current, second_factor_at: Time.current, second_factor_method: "totp")
      Portal::DocumentView.record!(publication.files.first, director)
      approval = Portal::Approval.record!(publication: publication, person: director, session: session, decision: "approved", comment: "Fine", ip: "10.0.0.1", user_agent: "Spec", locale: "en")
      PortalAdmin::SealApprovals.call
      [ publication, approval.reload ]
    end

    it "publishes for approval, naming the directors who may approve" do
      post accounting_portal_publications_path, params: publish_params(requires_approval: "1", approver_ids: [ director.id ], approvals_required: "all")

      publication = Portal::Publication.last
      expect(publication).to have_attributes(requires_approval: true, approvals_required: "all")
      expect(publication.approvers).to eq([ director ])
    end

    it "refuses to ask for approval without an approver" do
      post accounting_portal_publications_path, params: publish_params(requires_approval: "1")
      follow_redirect!
      expect(response.body).to include("name at least one person")
      expect(Portal::Publication.count).to eq(0)
    end

    it "shows where the approval stands, with each decision and whether its proof verifies" do
      approved_publication

      get accounting_portal_publications_path

      expect(response.body).to include("approved", "Dora Director", "sealed", "Proof (PDF)", "verifies")
    end

    it "gives the proof of approval as a PDF" do
      publication, approval = approved_publication

      get proof_accounting_portal_publication_path(publication.token, approval_id: approval.id)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(PDF::Reader.new(StringIO.new(response.body)).pages.first.text).to include("Proof of approval")
    end

    it "does not give the proof of another company" do
      _publication, approval = approved_publication
      other_entity = create(:entity)
      sign_in create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: other_entity) }

      get proof_accounting_portal_publication_path("x", approval_id: approval.id)

      expect(response).to have_http_status(:not_found).or have_http_status(:redirect)
      expect(response.media_type).not_to eq("application/pdf")
    end

    it "lets the firm require the client's approval for the closing" do
      patch settings_accounting_portal_publications_path, params: { client_approval_required: "1" }

      expect(entity.reload.client_approval_required).to be(true)
      expect(Accounting::AuditLog.where(action: "client_approval_required_changed").count).to eq(1)
    end

    it "is for those who manage the portal" do
      sign_in reader
      patch settings_accounting_portal_publications_path, params: { client_approval_required: "1" }
      expect(entity.reload.client_approval_required).to be(false)
    end
  end
end
