require "rails_helper"

RSpec.describe "Accounting::Settings::Accounts", type: :request do
  include_context 'with entity'

  let(:admin)   { create(:user, role: :admin) }
  let(:manager) { create(:user, role: :manager) }

  let!(:admin_membership)   { create(:user_entity, :admin,   user: admin,   entity: entity) }
  let!(:manager_membership) { create(:user_entity, :manager, user: manager, entity: entity) }

  let!(:parent_account) do
    create(:account, code: "600000", label_fr: "Charges d'exploitation",
           account_class: 6, is_leaf: false)
  end
  let!(:child_account) do
    create(:account, code: "604000", label_fr: "Services divers",
           account_class: 6, parent: parent_account)
  end

  before { sign_in admin }

  describe "GET /accounting/settings/accounts" do
    it "returns 200" do
      get accounting_settings_accounts_path
      expect(response).to have_http_status(:ok)
    end

    it "filters by text on code or label" do
      get accounting_settings_accounts_path, params: { q: { q: "services" } }
      expect(response.body).to include("604000").and not_include("600000")
    end

    it "combines the text filter with the class filter" do
      get accounting_settings_accounts_path, params: { account_class: 6, q: { q: "604" } }
      expect(response.body).to include("604000").and not_include("600000")
    end

    it "filters by class when ?account_class= is given" do
      get accounting_settings_accounts_path, params: { account_class: 6 }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/settings/accounts with column filters" do
    let!(:inactive_account) { create(:account, code: "699999", label_fr: "ZZInactive", account_type: :revenue, active: false) }

    it "filters on status and type, sorts by code" do
      get accounting_settings_accounts_path, params: { f: { active: %w[false] } }
      expect(response.body).to include("ZZInactive").and not_include("Services divers")
      get accounting_settings_accounts_path, params: { f: { account_type: %w[revenue] } }
      expect(response.body).to include("ZZInactive").and not_include("Services divers")
      get accounting_settings_accounts_path, params: { sort: "code", dir: "desc" }
      expect(response.body.index("ZZInactive")).to be < response.body.index("Services divers")
    end

    it "keeps the class tab when filtering" do
      get accounting_settings_accounts_path, params: { account_class: "6", f: { active: %w[false] } }
      expect(response.body).to include("account_class").and include("ZZInactive")
    end
  end

  describe "GET /accounting/settings/accounts/:id/edit" do
    it "returns 200" do
      get edit_accounting_settings_account_path(child_account)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /accounting/settings/accounts/:id" do
    context "updating allowed fields" do
      it "updates label_fr and redirects" do
        patch accounting_settings_account_path(child_account),
              params: { accounting_account: { label_fr: "Services divers (modifié)" } }
        expect(response).to redirect_to(accounting_settings_accounts_path(account_class: child_account.account_class))
        expect(child_account.reload.label_fr).to eq("Services divers (modifié)")
      end

      it "updates active status" do
        patch accounting_settings_account_path(child_account),
              params: { accounting_account: { active: false } }
        expect(child_account.reload.active).to be false
      end
    end

    context "attempting to change the code" do
      it "ignores code change and still updates" do
        patch accounting_settings_account_path(child_account),
              params: { accounting_account: { code: "999999", label_fr: "Updated" } }
        expect(child_account.reload.code).to eq("604000")
        expect(child_account.reload.label_fr).to eq("Updated")
      end
    end

    context "with blank label" do
      it "returns 422" do
        patch accounting_settings_account_path(child_account),
              params: { accounting_account: { label_fr: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /accounting/settings/accounts/new" do
    it "returns 200 with parent_id param" do
      get new_accounting_settings_account_path,
          params: { parent_id: parent_account.id }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /accounting/settings/accounts" do
    let(:valid_attrs) do
      {
        parent_id:      child_account.id,
        code:           "6040001",
        label_fr:       "Matériel bureau",
        account_class:  6,
        account_type:   "expense",
        normal_balance: "debit"
      }
    end

    it "creates a custom account and redirects" do
      expect {
        post accounting_settings_accounts_path,
             params: { accounting_account: valid_attrs }
      }.to change(Accounting::Account, :count).by(1)
      expect(response).to redirect_to(accounting_settings_accounts_path(account_class: 6))
    end

    it "returns 422 with invalid params" do
      post accounting_settings_accounts_path,
           params: { accounting_account: valid_attrs.merge(code: "7000001") }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "access control" do
    before { sign_in manager }

    it "redirects manager away from settings" do
      get accounting_settings_accounts_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
