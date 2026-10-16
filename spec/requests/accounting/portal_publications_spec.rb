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
end
