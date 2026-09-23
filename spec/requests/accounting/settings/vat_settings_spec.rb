require "rails_helper"

RSpec.describe "Accounting::Settings::VatSettings", type: :request do
  include_context "with entity"

  let(:admin)     { create(:user, role: :admin) }
  let(:manager)   { create(:user, role: :manager) }

  let!(:admin_membership)   { create(:user_entity, :admin,   user: admin,   entity: entity) }
  let!(:manager_membership) { create(:user_entity, :manager, user: manager, entity: entity) }

  before { sign_in admin }

  describe "GET /accounting/settings/vat_settings/edit" do
    it "returns 200" do
      get edit_accounting_settings_vat_settings_path
      expect(response).to have_http_status(:ok)
    end

    it "refuses a manager" do
      sign_in manager
      get edit_accounting_settings_vat_settings_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end

  describe "PATCH /accounting/settings/vat_settings" do
    it "updates the entity's VAT settings and redirects" do
      patch accounting_settings_vat_settings_path, params: {
        entity: {
          vat_filing_frequency: "monthly",
          vat_regime:           "franchise",
          vat_scheme:           "mixed",
          vat_prorata_rate:     "75.50"
        }
      }
      expect(response).to redirect_to(edit_accounting_settings_vat_settings_path)
      entity.reload
      expect(entity.vat_filing_frequency).to eq("monthly")
      expect(entity.vat_regime).to eq("franchise")
      expect(entity).to be_vat_scheme_mixed
      expect(entity.vat_prorata_rate).to eq(BigDecimal("75.50"))
    end

    it "accepts clearing the prorata rate back to nil" do
      entity.update!(vat_scheme: :mixed, vat_prorata_rate: "80.00")
      patch accounting_settings_vat_settings_path, params: {
        entity: { vat_filing_frequency: "quarterly", vat_regime: "normal", vat_scheme: "mixed", vat_prorata_rate: "" }
      }
      expect(entity.reload.vat_prorata_rate).to be_nil
    end

    it "refuses a manager" do
      sign_in manager
      patch accounting_settings_vat_settings_path, params: { entity: { vat_regime: "franchise" } }
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
