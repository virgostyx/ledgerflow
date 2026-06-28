require "rails_helper"

RSpec.describe "Accounting::Settings::BankAccounts", type: :request do
  include_context "with_pcmn_accounts"

  let(:admin) { create(:user, role: :admin) }
  let(:manager) { create(:user, role: :manager) }

  let!(:admin_membership)   { create(:user_entity, :admin,   user: admin,   entity: entity) }
  let!(:manager_membership) { create(:user_entity, :manager, user: manager, entity: entity) }

  let!(:bank_journal)  { create(:journal, :bank, default_account: account_550) }
  let!(:bank_account)  { create(:bank_account, journal: bank_journal, iban: "BE71096123456769") }

  before { sign_in admin }

  describe "GET /accounting/settings/bank_accounts" do
    it "returns 200" do
      get accounting_settings_bank_accounts_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/settings/bank_accounts/new" do
    it "returns 200" do
      get new_accounting_settings_bank_account_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /accounting/settings/bank_accounts" do
    let(:valid_attrs) do
      {
        label_fr:           "BNP Compte courant",
        journal_code:       "BNP1",
        iban:               "BE68539007547034",
        bic:                "GEBABEBB",
        default_account_id: account_550.id,
        currency:           "EUR"
      }
    end

    it "creates journal + bank account and redirects" do
      expect {
        post accounting_settings_bank_accounts_path,
             params: { bank_account_form: valid_attrs }
      }.to change(Accounting::BankAccount, :count).by(1)
         .and change(Accounting::Journal, :count).by(1)
      expect(response).to redirect_to(accounting_settings_bank_accounts_path)
    end

    it "returns 422 with an invalid IBAN" do
      post accounting_settings_bank_accounts_path,
           params: { bank_account_form: valid_attrs.merge(iban: "INVALID") }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /accounting/settings/bank_accounts/:id/edit" do
    it "returns 200" do
      get edit_accounting_settings_bank_account_path(bank_account)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /accounting/settings/bank_accounts/:id" do
    it "updates label and redirects" do
      patch accounting_settings_bank_account_path(bank_account),
            params: { accounting_bank_account: { label_fr: "ING Principal (modifié)" } }
      expect(response).to redirect_to(accounting_settings_bank_accounts_path)
      expect(bank_account.reload.label_fr).to eq("ING Principal (modifié)")
    end

    it "returns 422 with blank label" do
      patch accounting_settings_bank_account_path(bank_account),
            params: { accounting_bank_account: { label_fr: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /accounting/settings/bank_accounts/:id" do
    context "when no transactions exist" do
      it "destroys and redirects" do
        expect {
          delete accounting_settings_bank_account_path(bank_account)
        }.to change(Accounting::BankAccount, :count).by(-1)
        expect(response).to redirect_to(accounting_settings_bank_accounts_path)
      end
    end

    context "when transactions exist" do
      before { create(:bank_transaction, bank_account: bank_account) }

      it "redirects with alert and does not destroy" do
        expect {
          delete accounting_settings_bank_account_path(bank_account)
        }.not_to change(Accounting::BankAccount, :count)
        expect(response).to redirect_to(accounting_settings_bank_accounts_path)
      end
    end
  end

  describe "access control" do
    before { sign_in manager }

    it "redirects manager away from settings" do
      get accounting_settings_bank_accounts_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
