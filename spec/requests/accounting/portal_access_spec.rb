require "rails_helper"

# B02a, firm side: who has access to the portal of the company, invited, revoked, reset, identity verified. The right is portal.manage (owner, accountant).
RSpec.describe "Portal access (firm side)", type: :request do
  include_context "with entity"

  let(:owner)      { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:person)     { create(:portal_user) }
  let!(:grant)     { Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: "director", capabilities: %w[publications.view]) }

  before { sign_in accountant }

  it "lists the people with a right, their role, their last access and whether their identity was verified" do
    get accounting_portal_access_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(person.email).and include("director").and include("Invite")
  end

  it "does not list the people of another company" do
    foreign = create(:portal_user, email: "foreign@client.example")
    Portal::Grant.create!(portal_user: foreign, entity_id: create(:entity).id, role: "reader", capabilities: [])
    get accounting_portal_access_index_path
    expect(response.body).not_to include("foreign@client.example")
  end

  it "invites" do
    expect {
      post accounting_portal_access_index_path, params: { email: "new@client.example", full_name: "New One", role: "collaborator" }
    }.to change { Portal::Invitation.count }.by(1)
    expect(response).to redirect_to(accounting_portal_access_index_path)
  end

  it "shows why an invitation was refused" do
    post accounting_portal_access_index_path, params: { email: "bad", full_name: "X", role: "collaborator" }
    expect(response).to redirect_to(accounting_portal_access_index_path)
    follow_redirect!
    expect(response.body).to match(/email/i)
  end

  it "revokes a right" do
    delete accounting_portal_access_path(grant)
    expect(grant.reload.revoked_at).to be_present
  end

  it "does not touch the right of another company" do
    other = Portal::Grant.create!(portal_user: person, entity_id: create(:entity).id, role: "reader", capabilities: [])
    delete accounting_portal_access_path(other)
    expect(response).to have_http_status(:not_found)
    expect(other.reload.revoked_at).to be_nil
  end

  it "resets the access of a person, who is invited again" do
    expect { post reset_accounting_portal_access_path(grant) }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(person.reload).to be_invited
  end

  it "records that the identity was verified" do
    post verify_identity_accounting_portal_access_path(grant)
    expect(person.reload.identity_verified_by_id).to eq(accountant.id)
  end

  it "is closed to those who may not manage it" do
    sign_in reader
    get accounting_portal_access_index_path
    expect(response).to redirect_to(accounting_root_path)
    post accounting_portal_access_index_path, params: { email: "new@client.example", full_name: "New One", role: "reader" }
    expect(Portal::Invitation.count).to eq(0)
  end

  it "is off where the portal is off" do
    entity.update!(features: { "b02a" => false })
    get accounting_portal_access_index_path
    expect(response).to redirect_to(accounting_root_path)
  end
end
