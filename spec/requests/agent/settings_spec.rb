require "rails_helper"

# A01: the owner turns the agent on for the entity and picks how long conversations are kept. Nobody else does. (The consent of A04 will stand in front of "on".)
RSpec.describe "The agent's settings (A01)", type: :request do
  include_context "with_open_fiscal_year"

  let(:owner)      { create(:user, role: :accountant) }
  let(:accountant) { create(:user, role: :accountant) }
  let!(:owner_membership) { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before { entity.update!(features: entity.features.merge("agent" => true)) }

  it "shows the owner where the agent stands: off, 90 days" do
    sign_in owner

    get agent_setting_path

    expect(response.body).to include("Assistant settings", "90")
    expect(Agent::Setting.for_current_entity).not_to be_enabled
  end

  it "lets the owner turn the agent on and change the retention" do
    sign_in owner

    patch agent_setting_path, params: { agent_setting: { enabled: "1", retention_days: "30" } }

    expect(response).to redirect_to(agent_setting_path)
    expect(Agent::Setting.for_current_entity).to have_attributes(enabled: true, retention_days: 30)
  end

  it "refuses a retention that is not one of the choices" do
    sign_in owner

    patch agent_setting_path, params: { agent_setting: { retention_days: "7" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Agent::Setting.for_current_entity.retention_days).to eq(90)
  end

  it "is the owner's alone: an accountant changes nothing" do
    sign_in accountant

    patch agent_setting_path, params: { agent_setting: { enabled: "1" } }

    expect(Agent::Setting.for_current_entity).not_to be_enabled
  end

  it "is closed while the agent feature of the entity is off" do
    entity.update!(features: entity.features.merge("agent" => false))
    sign_in owner

    get agent_setting_path

    expect(response).to redirect_to(accounting_root_path)
  end

  it "is reachable from the entity settings, where the feature is turned on" do
    sign_in owner

    get edit_accounting_settings_entity_path

    expect(response.body).to include(agent_setting_path)
  end
end
