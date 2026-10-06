require "rails_helper"

# A01: the owner turns the agent on for the entity and picks how long conversations are kept. Nobody else does. (The consent of A04 will stand in front of "on".)
EXPECTED_CONSENT_DIGEST = "8d2a8ddd4051".freeze

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

  describe "the data processing terms" do
    it "shows the terms to the owner: who receives the data, what is sent, what is masked, what the owner must have validated" do
      sign_in owner

      get agent_setting_path

      expect(response.body).to include("Anthropic", Agent::Config.settings[:models][:chat_default], "PERSONNE_017", "data protection officer", Agent::Consent::VERSION)
    end

    it "keeps the assistant off until the terms are accepted: turning it on without accepting is refused" do
      sign_in owner

      patch agent_setting_path, params: { agent_setting: { enabled: "1" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Accept the data processing terms")
      expect(Agent::Setting.for_current_entity).not_to be_enabled
      expect(Agent::Consent.count).to eq(0)
    end

    it "records who accepted which version of the terms, and when, and turns the assistant on" do
      sign_in owner

      patch agent_setting_path, params: { agent_setting: { enabled: "1", retention_days: "30" }, accept_consent: "1" }

      expect(response).to redirect_to(agent_setting_path)
      expect(Agent::Setting.for_current_entity).to have_attributes(enabled: true, retention_days: 30)
      expect(Agent::Consent.last).to have_attributes(version: Agent::Consent::VERSION, accepted_by: owner)
      expect(Agent::Consent.last.accepted_at).to be_within(1.minute).of(Time.current)
      expect(Accounting::AuditLog.where(auditable_type: "Agent::Consent", action: "create")).to be_present
    end

    it "does not ask again while the accepted terms are the current ones" do
      accept_agent_consent!
      sign_in owner

      patch agent_setting_path, params: { agent_setting: { enabled: "1" } }

      expect(response).to redirect_to(agent_setting_path)
      expect(Agent::Setting.for_current_entity).to be_enabled
    end

    it "asks again when the text of the terms has changed, and the assistant is unavailable meanwhile" do
      accept_agent_consent!
      Agent::Setting.for_current_entity.update!(enabled: true)
      Agent::Consent.update_all(version: "2020-01-01")
      sign_in owner

      get agent_setting_path

      expect(response.body).to include("I have read these terms")
      expect(Agent::Access.check(Agent::Context.build(user: owner, entity: entity, locale: :en))).to eq(:consent_missing)
    end

    it "is not something an accountant can accept" do
      sign_in accountant

      patch agent_setting_path, params: { agent_setting: { enabled: "1" }, accept_consent: "1" }

      expect(Agent::Consent.count).to eq(0)
    end

    it "has a text whose version moves when the text does" do
      digest = Digest::SHA256.hexdigest(File.read(Rails.root.join("app/views/agent/settings/_consent.html.erb")))[0, 12]

      # when this fails: the text of the terms changed. Bump Agent::Consent::VERSION, then put the new digest here.
      expect([ Agent::Consent::VERSION, digest ]).to eq([ "2026-10-06", EXPECTED_CONSENT_DIGEST ])
    end
  end

  describe "what goes to the language model" do
    it "shows each class of data with the mode it has: the prudent defaults to begin with" do
      sign_in owner

      get agent_setting_path

      expect(response.body).to include("Names of people and companies", "Bank account numbers", "VAT and company numbers")
      expect(Agent::Setting.for_current_entity.modes).to eq("public_ref" => "send", "financial" => "send", "personal" => "mask", "bank_identifier" => "mask", "tax_identifier" => "mask", "free_text" => "send")
    end

    it "lets the owner change a mode, and writes the change in the audit trail" do
      sign_in owner

      patch agent_setting_path, params: { agent_setting: { data_class_modes: { personal: "block", free_text: "mask", financial: "" } } }

      setting = Agent::Setting.for_current_entity
      expect(setting.mode_for(:personal)).to eq("block")
      expect(setting.mode_for(:free_text)).to eq("mask")
      expect(setting.mode_for(:financial)).to eq("send") # a blank mode is the default again
      log = Accounting::AuditLog.where(auditable_type: "Agent::Setting", action: "update").last
      expect(log.payload.to_s).to include("personal")
      expect(log.user_id).to eq(owner.id)
    end

    it "refuses a mode or a class that does not exist" do
      sign_in owner

      patch agent_setting_path, params: { agent_setting: { data_class_modes: { personal: "reveal" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Agent::Setting.for_current_entity.mode_for(:personal)).to eq("mask")
    end

    it "blocks everything but the aggregates in restricted mode, whatever the owner chose" do
      sign_in owner

      patch agent_setting_path, params: { agent_setting: { restricted: "1", data_class_modes: { personal: "send" } } }

      setting = Agent::Setting.for_current_entity
      expect(setting.modes).to eq("public_ref" => "send", "financial" => "send", "personal" => "block", "bank_identifier" => "block", "tax_identifier" => "block", "free_text" => "block")
    end

    it "is not something an accountant can change" do
      sign_in accountant

      patch agent_setting_path, params: { agent_setting: { data_class_modes: { personal: "send" } } }

      expect(Agent::Setting.for_current_entity.mode_for(:personal)).to eq("mask")
    end
  end

  describe "the privacy page, for everyone who may use the assistant" do
    before { enable_agent! }

    it "says what is sent, to whom, for how long, and which terms were accepted" do
      Agent::Setting.for_current_entity.update!(data_class_modes: { "free_text" => "block" })
      sign_in accountant

      get agent_privacy_path

      expect(response.body).to include("Sent as it is", "Masked", "Never sent", "Anthropic", "90 days", "Version #{Agent::Consent::VERSION}")
    end

    it "says when only the aggregates are sent" do
      Agent::Setting.for_current_entity.update!(restricted: true)
      sign_in accountant

      get agent_privacy_path

      expect(response.body).to include("Restricted mode")
    end
  end

  it "lets the owner turn the agent on and change the retention" do
    accept_agent_consent!
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
