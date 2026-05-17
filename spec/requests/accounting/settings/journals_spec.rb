require "rails_helper"

RSpec.describe "Accounting::Settings::Journals", type: :request do
  include_context "with_pcmn_accounts"
  include_context "with_open_fiscal_year"

  let(:admin)     { create(:user, role: :admin) }
  let(:manager)   { create(:user, role: :manager) }

  let!(:journal) { create(:journal, :purchase, default_account: account_440) }

  before { sign_in admin }

  describe "GET /accounting/settings/journals" do
    it "returns 200" do
      get accounting_settings_journals_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/settings/journals/new" do
    it "returns 200" do
      get new_accounting_settings_journal_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /accounting/settings/journals" do
    let(:valid_attrs) do
      {
        code:               "BNQ2",
        label_fr:           "Banque BNP",
        journal_type:       "bank",
        sequence_prefix:    "BNQ2",
        default_account_id: account_550.id
      }
    end

    it "creates a journal and redirects" do
      expect {
        post accounting_settings_journals_path,
             params: { accounting_journal: valid_attrs }
      }.to change(Accounting::Journal, :count).by(1)
      expect(response).to redirect_to(accounting_settings_journals_path)
    end

    it "returns 422 with invalid params" do
      post accounting_settings_journals_path,
           params: { accounting_journal: { code: nil } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /accounting/settings/journals/:id/edit" do
    it "returns 200" do
      get edit_accounting_settings_journal_path(journal)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /accounting/settings/journals/:id" do
    it "updates and redirects" do
      patch accounting_settings_journal_path(journal),
            params: { accounting_journal: { label_fr: "Achats (modifié)" } }
      expect(response).to redirect_to(accounting_settings_journals_path)
      expect(journal.reload.label_fr).to eq("Achats (modifié)")
    end

    it "returns 422 with invalid params" do
      patch accounting_settings_journal_path(journal),
            params: { accounting_journal: { code: nil } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /accounting/settings/journals/:id" do
    context "when journal has no entries" do
      it "destroys and redirects" do
        expect {
          delete accounting_settings_journal_path(journal)
        }.to change(Accounting::Journal, :count).by(-1)
        expect(response).to redirect_to(accounting_settings_journals_path)
      end
    end

    context "when journal has entries" do
      before { create(:journal_entry, journal: journal, fiscal_year: fiscal_year) }

      it "redirects with alert and does not destroy" do
        expect {
          delete accounting_settings_journal_path(journal)
        }.not_to change(Accounting::Journal, :count)
        expect(response).to redirect_to(accounting_settings_journals_path)
      end
    end
  end

  describe "PATCH /accounting/settings/journals/:id/toggle_active" do
    context "when journal is deactivatable" do
      it "toggles active and redirects" do
        patch toggle_active_accounting_settings_journal_path(journal)
        expect(journal.reload.active).to be false
        expect(response).to redirect_to(accounting_settings_journals_path)
      end
    end

    context "when journal has draft entries" do
      before { create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year) }

      it "redirects with alert without changing active" do
        patch toggle_active_accounting_settings_journal_path(journal)
        expect(journal.reload.active).to be true
        expect(response).to redirect_to(accounting_settings_journals_path)
      end
    end
  end

  describe "access control" do
    before { sign_in manager }

    it "redirects manager away from settings" do
      get accounting_settings_journals_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
