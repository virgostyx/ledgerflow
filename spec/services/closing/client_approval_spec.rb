require "rails_helper"

# B02c, criterion 8: with the option on, step 18 of the closing stays blocked until the client's approval of the year exists.
RSpec.describe "Closing and the client's approval" do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  let(:owner)    { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:director) { create(:portal_user, identity_verified_at: Time.current, identity_verified_by: owner) }
  let(:run)      { Closing::OpenRun.call(fiscal_year: fiscal_year, user: owner)[:run] }
  let(:pdf)      { { filename: "accounts.pdf", content_type: "application/pdf", data: Prawn::Document.new { |d| d.text "Accounts" }.render } }

  before { Portal::Grant.create!(portal_user: director, entity_id: entity.id, role: "director", capabilities: %w[publications.view accounts.approve]) }

  def publish(period: (fiscal_year.start_date..fiscal_year.end_date))
    PortalAdmin::Publish.call(entity: entity, kind: "situation", title: "Accounts", files: [ pdf ], by: owner, requires_approval: true, approvers: [ director ], period: period)[:publication]
  end

  def approve(publication)
    session = Portal::Session.create!(portal_user: director, token_digest: SecureRandom.hex(8), last_seen_at: Time.current, second_factor_at: Time.current, second_factor_method: "totp")
    Portal::DocumentView.record!(publication.files.first, director)
    Portal::Approval.record!(publication: publication, person: director, session: session, decision: "approved", comment: nil, ip: "10.0.0.1", user_agent: "Spec", locale: "en")
  end

  it "asks nothing when the option is off" do
    expect(Closing::ClientApproval.required?(entity)).to be(false)
  end

  it "is not satisfied until an approved publication covers the year, and then it is" do
    publication = publish
    expect(Closing::ClientApproval.satisfied?(fiscal_year)).to be(false)
    approve(publication)
    expect(Closing::ClientApproval.satisfied?(fiscal_year)).to be(true)
  end

  it "is not satisfied by a publication of another period, a refusal or a withdrawn publication" do
    approve(publish(period: (fiscal_year.end_date + 1)..(fiscal_year.end_date + 30)))
    expect(Closing::ClientApproval.satisfied?(fiscal_year)).to be(false)

    publication = publish
    approve(publication)
    PortalAdmin::Withdraw.call(publication: publication, by: owner, reason: "wrong")
    expect(Closing::ClientApproval.satisfied?(fiscal_year)).to be(false)
  end

  it "keeps the approval of the closing refused while the client has not approved" do
    entity.update!(client_approval_required: true)

    result = Closing::Approve.call(run: run, user: owner, comment: "Done")

    expect(result).to be_failure
    expect(result.message).to match(/client's approval/)
    expect(run.reload).not_to be_closed
  end
end
