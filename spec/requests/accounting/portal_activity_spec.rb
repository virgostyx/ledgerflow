require "rails_helper"

# B02a: "Portal activity" - sign-ins, readings, downloads, by company and by person - and the unusual behaviours; and the review of the accesses.
RSpec.describe "Portal activity (firm side)", type: :request do
  include_context "with entity"

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:person)     { create(:portal_user, full_name: "Ann Client") }
  let(:other)      { create(:portal_user, full_name: "Bob Elsewhere") }

  before do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: "director", capabilities: %w[publications.view])
    Portal::Grant.create!(portal_user: other, entity_id: create(:entity).id, role: "director", capabilities: %w[publications.view])
    sign_in accountant
  end

  it "lists what the people of this company did, not what others did" do
    Portal::Event.record!("publication_downloaded", user: person, entity_id: entity.id, target_token: "tok123")
    Portal::Event.record!("sign_in", user: person)
    Portal::Event.record!("publication_downloaded", user: other, entity_id: Portal::Grant.where(portal_user: other).first.entity_id, target_token: "tokOTHER")

    get accounting_portal_activity_index_path

    expect(response.body).to include("Ann Client").and include("publication_downloaded").and include("sign_in").and include("tok123")
    expect(response.body).to include("Portal activity")
    expect(response.body).not_to include("Bob Elsewhere")
    expect(response.body).not_to include("tokOTHER")
  end

  it "filters by person" do
    colleague = create(:portal_user, full_name: "Carl Colleague")
    Portal::Grant.create!(portal_user: colleague, entity_id: entity.id, role: "reader", capabilities: [])
    Portal::Event.record!("sign_in", user: person)
    Portal::Event.record!("sign_in", user: colleague)

    get accounting_portal_activity_index_path(person_id: person.id)

    expect(response.body).to include("Ann Client")
    expect(response.body).not_to include("Carl Colleague</td>")
  end

  it "points out the unusual: a burst of downloads, attempts outside the scope, repeated failures" do
    25.times { Portal::Event.record!("publication_downloaded", user: person, entity_id: entity.id, target_token: "t") }
    Portal::Event.record!("out_of_scope_attempt", user: person, entity_id: entity.id, target_token: "guess")
    6.times { Portal::Event.record!("sign_in_failed", user: person, email_tried: person.email) }

    get accounting_portal_activity_index_path

    expect(response.body).to include("Unusual").and include("downloads in 10 minutes").and include("outside their scope").and include("failed sign-ins")
  end

  it "says nothing unusual when there is nothing" do
    get accounting_portal_activity_index_path
    expect(response.body).to include("Nothing unusual")
  end

  it "shows the review of the accesses, with the inactive ones flagged, on the access page" do
    person.update_columns(last_seen_at: 100.days.ago)
    get accounting_portal_access_index_path
    expect(response.body).to include("not used for 90 days")
  end

  it "reinstates a suspended person" do
    person.update!(status: "suspended")
    grant = Portal::Grant.find_by(portal_user: person)
    post reinstate_accounting_portal_access_path(grant)
    expect(person.reload).to be_active
  end

  it "is closed to those who may not manage the portal" do
    sign_in reader
    get accounting_portal_activity_index_path
    expect(response).to redirect_to(accounting_root_path)
  end
end
