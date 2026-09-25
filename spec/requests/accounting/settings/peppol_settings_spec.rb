require "rails_helper"

RSpec.describe "Accounting::Settings::PeppolSettings", type: :request do
  include_context "with entity"

  let(:admin)   { create(:user, role: :admin) }
  let(:manager) { create(:user, role: :manager) }

  let!(:admin_membership)   { create(:user_entity, :admin,   user: admin,   entity: entity) }
  let!(:manager_membership) { create(:user_entity, :manager, user: manager, entity: entity) }

  before { sign_in admin }

  describe "GET /accounting/settings/peppol_settings/edit" do
    it "returns 200 and shows the webhook URL of the entity once an Access Point is chosen" do
      entity.update!(peppol_access_point: :simulator)
      get edit_accounting_settings_peppol_settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/peppol/webhooks/#{entity.peppol_webhook_token}")
    end

    it "asks for the credentials of the chosen provider, without ever showing a secret" do
      entity.update!(peppol_access_point: :digiteal, peppol_credentials: { "api_key" => "TOPSECRET", "webhook_secret" => "OTHERSECRET" })
      get edit_accounting_settings_peppol_settings_path
      expect(response.body).to include("API key", "Webhook secret", "already set")
      expect(response.body).not_to include("TOPSECRET", "OTHERSECRET")
    end

    it "refuses a manager" do
      sign_in manager
      get edit_accounting_settings_peppol_settings_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end

  describe "PATCH /accounting/settings/peppol_settings" do
    def patch_settings(entity: {}, credentials: {})
      patch accounting_settings_peppol_settings_path, params: { entity: entity, credentials: credentials }
    end

    it "saves the Access Point and the participant identifier" do
      patch_settings(entity: { peppol_access_point: "simulator", peppol_participant_id: " 0208:0123456789 " })
      expect(response).to redirect_to(edit_accounting_settings_peppol_settings_path)
      expect(entity.reload).to have_attributes(peppol_access_point: "simulator", peppol_participant_id: "0208:0123456789")
    end

    it "stores the credentials of the provider" do
      patch_settings(entity: { peppol_access_point: "digiteal" }, credentials: { api_key: "k1", webhook_secret: "s1" })
      expect(entity.reload.peppol_credentials).to eq("api_key" => "k1", "webhook_secret" => "s1")
    end

    it "keeps a stored secret when its field is left empty" do
      entity.update!(peppol_access_point: :digiteal, peppol_credentials: { "api_key" => "old", "webhook_secret" => "old-s" })
      patch_settings(entity: { peppol_access_point: "digiteal" }, credentials: { api_key: "", webhook_secret: "new-s" })
      expect(entity.reload.peppol_credentials).to eq("api_key" => "old", "webhook_secret" => "new-s")
    end

    it "drops the credentials of the previous provider when the provider changes" do
      entity.update!(peppol_access_point: :digiteal, peppol_credentials: { "api_key" => "old", "webhook_secret" => "old-s" })
      patch_settings(entity: { peppol_access_point: "simulator" })
      expect(entity.reload.peppol_credentials).to eq({})
    end

    it "re-renders with the errors when the data is invalid" do
      patch_settings(entity: { peppol_access_point: "digiteal", peppol_participant_id: "nonsense" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Webhook secret")
      expect(entity.reload.peppol_access_point).to be_nil
    end

    it "lets the Access Point be removed" do
      entity.update!(peppol_access_point: :simulator)
      patch_settings(entity: { peppol_access_point: "" })
      expect(entity.reload.peppol_access_point).to be_nil
    end

    it "refuses a manager" do
      sign_in manager
      patch_settings(entity: { peppol_access_point: "simulator" })
      expect(entity.reload.peppol_access_point).to be_nil
    end
  end

  describe "POST /accounting/settings/peppol_settings/simulate_incoming" do
    before { entity.update!(peppol_access_point: :simulator, peppol_participant_id: "0208:0123456789") }

    it "books a simulated incoming invoice and says so" do
      create(:fiscal_year, status: :open)
      expect { post simulate_incoming_accounting_settings_peppol_settings_path }.to change(Accounting::Invoice, :count).by(1)
      expect(response).to redirect_to(edit_accounting_settings_peppol_settings_path)
      expect(flash[:notice]).to include("Simulated")
    end

    it "tells why nothing was booked" do
      post simulate_incoming_accounting_settings_peppol_settings_path
      expect(flash[:alert]).to match(/open fiscal year/)
    end

    it "does nothing for an entity that is not on the simulator" do
      entity.update!(peppol_access_point: nil)
      expect { post simulate_incoming_accounting_settings_peppol_settings_path }.not_to change(Accounting::Invoice, :count)
      expect(flash[:alert]).to be_present
    end

    it "shows the button only with the simulator" do
      get edit_accounting_settings_peppol_settings_path
      expect(response.body).to include("Simulate an incoming invoice")
      entity.update!(peppol_access_point: nil)
      get edit_accounting_settings_peppol_settings_path
      expect(response.body).not_to include("Simulate an incoming invoice")
    end

    it "refuses a manager" do
      sign_in manager
      expect { post simulate_incoming_accounting_settings_peppol_settings_path }.not_to change(Accounting::Invoice, :count)
    end
  end
end
