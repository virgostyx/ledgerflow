require "rails_helper"

# B02c, decision of 2026-10-17: a button of the closing assistant publishes the statements of the year to the client portal for approval, with the period of the year, so that step 18 waits for it.
RSpec.describe "Closing: publish the accounts for the client's approval", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  let(:owner)    { create(:user, role: :admin).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:reader)   { create(:user, role: :manager).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:director) { create(:portal_user, full_name: "Dora Director", identity_verified_at: Time.current, identity_verified_by: owner) }
  let!(:misc)    { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let(:run)      { Closing::OpenRun.call(fiscal_year: fiscal_year, user: owner)[:run] }

  before do
    entity.update!(vat_regime: :franchise)
    Portal::Grant.create!(portal_user: director, entity_id: entity.id, role: "director", capabilities: %w[publications.view accounts.approve])
    sign_in owner
  end

  it "publishes the balance sheet and the income statement with the period of the year, for approval by the chosen directors" do
    expect { post publish_for_approval_accounting_closing_run_path(run), params: { approver_ids: [ director.id ], approvals_required: "all", message: "Please approve" } }
      .to change(Portal::Publication, :count).by(1)

    publication = Portal::Publication.sole
    expect(publication).to have_attributes(kind: "situation", requires_approval: true, approvals_required: "all", period_start: fiscal_year.start_date, period_end: fiscal_year.end_date, message: "Please approve")
    expect(publication.files.map(&:filename)).to contain_exactly("R07_balance_sheet.pdf", "R08_income_statement.pdf")
    expect(publication.approvers).to eq([ director ])
    expect(Accounting::AuditLog.where(action: "closing_published_for_approval").count).to eq(1)
  end

  it "makes step 18 wait for that approval when the company requires it" do
    entity.update!(client_approval_required: true)
    post publish_for_approval_accounting_closing_run_path(run), params: { approver_ids: [ director.id ] }
    expect(Closing::ClientApproval.satisfied?(fiscal_year)).to be(false)

    publication = Portal::Publication.sole
    session = Portal::Session.create!(portal_user: director, token_digest: SecureRandom.hex(8), last_seen_at: Time.current, second_factor_at: Time.current, second_factor_method: "totp")
    Portal::DocumentView.record!(publication.files.first, director)
    Portal::Approval.record!(publication: publication, person: director, session: session, decision: "approved", comment: nil, ip: "10.0.0.1", user_agent: "Spec", locale: "en")

    expect(Closing::ClientApproval.satisfied?(fiscal_year)).to be(true)
  end

  it "publishes a new version when the accounts were already published for this year, which supersedes the approvals" do
    post publish_for_approval_accounting_closing_run_path(run), params: { approver_ids: [ director.id ] }
    first = Portal::Publication.sole

    post publish_for_approval_accounting_closing_run_path(run), params: { approver_ids: [ director.id ] }

    expect(Portal::Publication.count).to eq(2)
    expect(first.reload.replaced_by_id).to be_present
  end

  it "refuses without an approver, or with someone whose identity was not verified" do
    post publish_for_approval_accounting_closing_run_path(run), params: { approver_ids: [] }
    follow_redirect!
    expect(response.body).to include("name at least one person")

    unverified = create(:portal_user, identity_verified_at: nil)
    Portal::Grant.create!(portal_user: unverified, entity_id: entity.id, role: "director", capabilities: %w[accounts.approve])
    post publish_for_approval_accounting_closing_run_path(run), params: { approver_ids: [ unverified.id ] }
    expect(Portal::Publication.count).to eq(0)
  end

  it "shows the form in the step of the approval" do
    get accounting_closing_run_path(run)
    expect(response.body).to include("Ask the client to approve the accounts", "Dora Director", "Publish for approval")
  end

  it "is for those who manage the portal, and closed once the run is closed or the feature is off" do
    sign_in reader
    expect { post publish_for_approval_accounting_closing_run_path(run), params: { approver_ids: [ director.id ] } }.not_to change(Portal::Publication, :count)

    sign_in owner
    entity.update!(features: { "b02c" => false })
    expect { post publish_for_approval_accounting_closing_run_path(run), params: { approver_ids: [ director.id ] } }.not_to change(Portal::Publication, :count)
  end
end
