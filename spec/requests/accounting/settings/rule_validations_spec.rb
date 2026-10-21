require "rails_helper"

RSpec.describe "Accounting::Settings::RuleValidations", type: :request do
  include_context "with entity"

  let(:admin)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }

  let!(:admin_membership)      { create(:user_entity, :admin,      user: admin,      entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  let(:valid_params) do
    { rule_validation: { rule_key: "vat_declaration", validated_by_name: "Jane Doe", validated_by_title: "Chartered accountant",
                         validated_on: Date.current.to_s, reference: "Letter of 2026-10-20", note: "Cases 1 to 6" } }
  end

  before { sign_in admin }

  describe "GET index" do
    it "lists both rules, with their state" do
      Accounting::RuleValidation.create!(valid_params[:rule_validation])
      get accounting_settings_rule_validations_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("VAT declaration", "Annual accounts", "Jane Doe", "Not validated")
    end

    it "refuses an accountant" do
      sign_in accountant
      get accounting_settings_rule_validations_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end

  describe "POST create" do
    it "records the validation and audits it" do
      expect { post accounting_settings_rule_validations_path, params: valid_params }
        .to change { Accounting::RuleValidation.validated?("vat_declaration") }.from(false).to(true)
      expect(response).to redirect_to(accounting_settings_rule_validations_path)
      expect(Accounting::AuditLog.where(action: "rule_validated").count).to eq(1)
    end

    it "re-renders with the errors when the reference is missing" do
      params = valid_params.deep_merge(rule_validation: { reference: "" })
      post accounting_settings_rule_validations_path, params: params
      expect(response).to have_http_status(:unprocessable_content)
      expect(Accounting::RuleValidation.count).to eq(0)
    end

    it "refuses an accountant" do
      sign_in accountant
      expect { post accounting_settings_rule_validations_path, params: valid_params }
        .not_to change(Accounting::RuleValidation, :count)
    end
  end

  describe "PATCH revoke" do
    let!(:validation) { Accounting::RuleValidation.create!(valid_params[:rule_validation]) }

    it "revokes the validation and audits it" do
      expect { patch revoke_accounting_settings_rule_validation_path(validation) }
        .to change { Accounting::RuleValidation.validated?("vat_declaration") }.from(true).to(false)
      expect(Accounting::AuditLog.where(action: "rule_validation_revoked").count).to eq(1)
    end

    it "refuses an accountant" do
      sign_in accountant
      patch revoke_accounting_settings_rule_validation_path(validation)
      expect(Accounting::RuleValidation.validated?("vat_declaration")).to be(true)
    end
  end
end
