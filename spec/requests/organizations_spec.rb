require "rails_helper"

RSpec.describe "Organizations", type: :request do
  let(:alice) { create(:user, email: "alice@firm.test") }
  let(:bob)   { create(:user, email: "bob@firm.test", full_name: "Bob") }
  let!(:acme)   { create(:entity, name: "Acme") }
  let!(:bakery) { create(:entity, name: "Bakery") }

  before do
    create(:user_entity, :admin, user: alice, entity: acme)
    create(:user_entity, :accountant, user: alice, entity: bakery)
    create(:user_entity, :admin, user: bob, entity: bakery)
    sign_in alice
  end

  it "is made by a person, who becomes its owner, and gathers the dossiers they own" do
    post organizations_path, params: { organization: { name: "Firm" } }
    firm = Organization.find_by!(name: "Firm")
    expect(firm.owner?(alice)).to be(true)

    post add_entity_organization_path(firm), params: { entity_id: acme.id }
    expect(acme.reload.organization).to eq(firm)
    post add_entity_organization_path(firm), params: { entity_id: bakery.id } # she is only accountant there
    expect(flash[:alert]).to match(/Only the owner of a dossier/)
    expect(bakery.reload.organization).to be_nil

    get organization_path(firm)
    expect(response.body).to include("Acme", "alice@firm.test".split("@").first.then { alice.full_name })
  end

  it "gives access to nothing: a member sees only the dossiers they work in" do
    firm = Organization.create!(name: "Firm")
    OrganizationMembership.create!(organization: firm, user: alice, role: "owner")
    acme.update!(organization: firm)
    bakery.update!(organization: firm)
    OrganizationMembership.create!(organization: firm, user: bob, role: "member")

    sign_in bob
    get organization_path(firm)
    expect(response.body).to include("Bakery").and not_include("Acme")
    expect(response.body).to include("1 more dossier you have no access to")
  end

  it "is managed by its owners only, and keeps one" do
    firm = Organization.create!(name: "Firm")
    OrganizationMembership.create!(organization: firm, user: alice, role: "owner")
    mine = firm.organization_memberships.find_by(user: alice)

    post add_member_organization_path(firm), params: { email: "bob@firm.test", role: "member" }
    expect(firm.users).to include(bob)
    post add_member_organization_path(firm), params: { email: "nobody@firm.test" }
    expect(flash[:alert]).to match(/No one has that e-mail/)

    delete remove_member_organization_path(firm, membership_id: mine.id)
    expect(flash[:alert]).to match(/at least one owner/)
    expect(firm.users).to include(alice)

    sign_in bob
    post add_member_organization_path(firm), params: { email: "alice@firm.test" }
    expect(flash[:alert]).to match(/Only an owner/)
    patch organization_path(firm), params: { organization: { name: "Hijack" } }
    expect(firm.reload.name).to eq("Firm")
  end

  it "does not exist for someone who is not in it" do
    firm = Organization.create!(name: "Secret firm")
    get organization_path(firm)
    expect(response).to have_http_status(:not_found)
    get organizations_path
    expect(response.body).not_to include("Secret firm")
  end

  it "takes a dossier out only for its owner" do
    firm = Organization.create!(name: "Firm")
    OrganizationMembership.create!(organization: firm, user: alice, role: "owner")
    acme.update!(organization: firm)
    bakery.update!(organization: firm)
    delete remove_entity_organization_path(firm, entity_id: bakery.id)
    expect(flash[:alert]).to match(/Only the owner of a dossier/)
    delete remove_entity_organization_path(firm, entity_id: acme.id)
    expect(acme.reload.organization).to be_nil
  end
end
