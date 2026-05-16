require "rails_helper"

RSpec.describe "Accounting::FiscalYears", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:admin)     { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }

  before { sign_in admin }

  describe "GET /accounting/fiscal_years" do
    it "retourne 200" do
      get accounting_fiscal_years_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/fiscal_years/:id" do
    it "retourne 200" do
      get accounting_fiscal_year_path(fiscal_year)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/fiscal_years/new" do
    it "retourne 200" do
      get new_accounting_fiscal_year_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/fiscal_years/:id/edit" do
    it "retourne 200" do
      get edit_accounting_fiscal_year_path(fiscal_year)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /accounting/fiscal_years/:id" do
    context "avec des paramètres valides" do
      it "met à jour et redirige" do
        patch accounting_fiscal_year_path(fiscal_year),
              params: { accounting_fiscal_year: { year: fiscal_year.year } }
        expect(response).to redirect_to(accounting_fiscal_year_path(fiscal_year))
      end
    end

    context "avec des paramètres invalides" do
      it "retourne 422 et rerender :edit" do
        patch accounting_fiscal_year_path(fiscal_year),
              params: { accounting_fiscal_year: { year: nil } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "POST /accounting/fiscal_years" do
    let(:valid_attrs) do
      { year: 2027, start_date: "2027-01-01", end_date: "2027-12-31" }
    end

    before do
      fiscal_year.update!(status: :closed, closed_at: Time.current, closed_by_id: admin.id)
    end

    it "crée un exercice et redirige" do
      expect {
        post accounting_fiscal_years_path,
             params: { accounting_fiscal_year: valid_attrs }
      }.to change(Accounting::FiscalYear, :count).by(1)
    end

    it "retourne 422 si invalide" do
      post accounting_fiscal_years_path,
           params: { accounting_fiscal_year: { year: nil } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /accounting/fiscal_years/:id" do
    it "retourne 403" do
      delete accounting_fiscal_year_path(fiscal_year)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /accounting/fiscal_years/:id/close" do
    let!(:misc_journal) do
      create(:journal, code: "CLO", label_fr: "Clôture",
             journal_type: :misc, sequence_prefix: "CLO")
    end
    let!(:result_account) do
      create(:account, code: "699000", label_fr: "Résultat de l'exercice",
             account_type: :expense, normal_balance: :debit, account_class: 6)
    end
    let!(:purchase_journal) { create(:journal, :purchase) }

    def create_posted_entry
      entry = create(:journal_entry, :draft, journal: purchase_journal,
                     fiscal_year: fiscal_year,
                     entry_date: fiscal_year.start_date + 10)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604,
             debit: BigDecimal("500.00"), credit: BigDecimal("0"))
      create(:journal_entry_line, journal_entry: entry, account: account_440,
             debit: BigDecimal("0"), credit: BigDecimal("500.00"))
      entry.post!
    end

    context "exercice propre (sans brouillons)" do
      before { create_posted_entry }

      it "clôture l'exercice et redirige" do
        post close_accounting_fiscal_year_path(fiscal_year)
        expect(response).to redirect_to(accounting_fiscal_year_path(fiscal_year))
      end

      it "marque l'exercice comme clôturé" do
        post close_accounting_fiscal_year_path(fiscal_year)
        expect(fiscal_year.reload.status).to eq("closed")
      end
    end

    context "exercice avec des brouillons" do
      before do
        create(:journal_entry, :draft, journal: purchase_journal,
               fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1)
      end

      it "redirige avec une alerte" do
        post close_accounting_fiscal_year_path(fiscal_year)
        expect(response).to redirect_to(accounting_fiscal_year_path(fiscal_year))
      end

      it "ne clôture pas l'exercice" do
        post close_accounting_fiscal_year_path(fiscal_year)
        expect(fiscal_year.reload.status).to eq("open")
      end
    end

    context "exercice déjà clôturé" do
      before do
        fiscal_year.update!(status: :closed, closed_at: Time.current, closed_by_id: admin.id)
      end

      it "redirige avec une alerte" do
        post close_accounting_fiscal_year_path(fiscal_year)
        expect(response).to redirect_to(accounting_fiscal_year_path(fiscal_year))
      end
    end
  end
end
