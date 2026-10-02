require "rails_helper"

RSpec.describe "Accounting::Settings::Entities", type: :request do
  include_context "with entity"

  let(:admin)   { create(:user, role: :admin) }
  let(:manager) { create(:user, role: :manager) }

  let!(:admin_membership)   { create(:user_entity, :admin,   user: admin,   entity: entity) }
  let!(:manager_membership) { create(:user_entity, :manager, user: manager, entity: entity) }

  before { sign_in admin }

  describe "GET /accounting/settings/entity/edit" do
    it "returns 200 and shows the current values" do
      entity.update!(name: "Acme Belgium", city: "Namur")
      get edit_accounting_settings_entity_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Belgium", "Namur")
    end

    it "refuses a manager" do
      sign_in manager
      get edit_accounting_settings_entity_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end

  describe "PATCH /accounting/settings/entity" do
    let(:valid_params) do
      { entity: { name: "Acme", legal_name: "Acme SRL", legal_form: "SRL", vat_number: "BE0123456789",
                  country: "BE", address_line1: "Rue de la Loi 16", address_line2: "Bte 4",
                  zip_code: "1000", city: "Bruxelles" } }
    end

    it "updates the entity and redirects back to the form" do
      patch accounting_settings_entity_path, params: valid_params

      expect(response).to redirect_to(edit_accounting_settings_entity_path)
      expect(flash[:notice]).to be_present
      expect(entity.reload).to have_attributes(name: "Acme", legal_name: "Acme SRL", legal_form: "SRL",
                                               vat_number: "BE0123456789", address_line1: "Rue de la Loi 16",
                                               address_line2: "Bte 4", zip_code: "1000", city: "Bruxelles")
    end

    it "re-renders with errors when the name is blank" do
      patch accounting_settings_entity_path, params: { entity: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(entity.reload.name).not_to be_blank
    end

    it "re-renders with errors when the VAT number is malformed" do
      patch accounting_settings_entity_path, params: { entity: { vat_number: "XX123" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(entity.reload.vat_number).not_to eq("XX123")
    end

    it "ignores attributes that are not editable here" do
      other_user = create(:user)
      patch accounting_settings_entity_path,
            params: { entity: { name: "Acme", active: "false", created_by_id: other_user.id, vat_regime: "franchise" } }

      entity.reload
      expect(entity.active).to be true
      expect(entity.created_by_id).not_to eq(other_user.id)
      expect(entity.vat_regime).to eq("normal")
    end

    it "leaves other entities untouched" do
      other = ActsAsTenant.without_tenant { create(:entity, name: "Elsewhere") }
      patch accounting_settings_entity_path, params: valid_params

      expect(other.reload.name).to eq("Elsewhere")
    end

    it "refuses a manager" do
      sign_in manager
      patch accounting_settings_entity_path, params: valid_params

      expect(response).to redirect_to(accounting_root_path)
      expect(entity.reload.name).not_to eq("Acme")
    end
  end

  describe "settings dashboard" do
    it "links to the entity form" do
      get accounting_settings_root_path
      expect(response.body).to include(edit_accounting_settings_entity_path)
    end

    it "links the owner to users and roles" do
      get accounting_settings_root_path
      expect(response.body).to include(accounting_settings_memberships_path)
    end

    it "does not offer users and roles to an accountant" do
      sign_in create(:user, role: :accountant).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) }

      get accounting_settings_root_path

      expect(response.body).not_to include(accounting_settings_memberships_path)
    end
  end

  describe "four-eyes option (F01)" do
    let(:accountant) { create(:user, role: :accountant) }
    let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

    it "lets the owner require a second person, from an amount upward" do
      patch accounting_settings_entity_path, params: { entity: { four_eyes: "1", four_eyes_threshold: "500.00" } }

      expect(entity.reload.four_eyes).to be true
      expect(entity.four_eyes_threshold).to eq(500)
    end

    it "shows the option to the owner" do
      get edit_accounting_settings_entity_path

      expect(response.body).to include("entity[four_eyes]")
    end

    it "ignores the option when an accountant sends it" do
      sign_in accountant

      patch accounting_settings_entity_path, params: { entity: { four_eyes: "1" } }

      expect(entity.reload.four_eyes).to be false
    end
  end
end
