require "rails_helper"

RSpec.describe "Accounting::Settings::BankRules", type: :request do
  include_context "with entity"

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let(:account) { create(:account, code: "651100", label_fr: "Frais bancaires") }
  let!(:rule) { Accounting::BankRule.create!(name: "Bank fees", condition_type: "contains", condition_value: "frais de tenue", account: account) }

  before { sign_in accountant }

  it "lists the rules with what they say and where they book" do
    get accounting_settings_bank_rules_path

    expect(response.body).to include("Bank fees", "frais de tenue", "651100")
  end

  it "changes the priority, the score, the action and switches a rule off" do
    patch accounting_settings_bank_rule_path(rule), params: { bank_rule: { priority: 5, score: 90, action: "book_draft", active: "0" } }

    expect(rule.reload).to have_attributes(priority: 5, score: 90, action: "book_draft", active: false)
  end

  it "says what is wrong with a score out of range" do
    patch accounting_settings_bank_rule_path(rule), params: { bank_rule: { score: 100 } }

    expect(rule.reload.score).to eq(80)
    expect(flash[:alert]).to be_present
  end

  it "deletes a rule" do
    expect { delete accounting_settings_bank_rule_path(rule) }.to change(Accounting::BankRule, :count).by(-1)
  end

  it "is closed to an assistant and while the feature is off" do
    sign_out accountant
    sign_in assistant
    expect { delete accounting_settings_bank_rule_path(rule) }.not_to change(Accounting::BankRule, :count)

    sign_out assistant
    sign_in accountant
    entity.update!(features: entity.features.merge("f02" => false))
    get accounting_settings_bank_rules_path
    expect(response).to redirect_to(accounting_root_path)
  end

  it "only reaches the rules of this entity" do
    foreign = ActsAsTenant.with_tenant(create(:entity)) do
      Accounting::BankRule.create!(name: "x", condition_type: "contains", condition_value: "y", account: create(:account, code: "613000"))
    end

    delete accounting_settings_bank_rule_path(foreign)

    expect(response).to have_http_status(:not_found)
  end
end
