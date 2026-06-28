require "rails_helper"

RSpec.describe "Accounting::Reports", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:journal)    { create(:journal, :purchase) }

  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  let!(:expense_account) do
    create(:account, code: "604000", label_fr: "Services",
           account_type: :expense, normal_balance: :debit, account_class: 6)
  end
  let!(:liability_account) do
    create(:account, code: "440000", label_fr: "Fournisseurs",
           account_type: :liability, normal_balance: :credit, account_class: 4)
  end

  before { sign_in accountant }

  def create_posted_entry(project_id: nil)
    entry = create(:journal_entry, :draft, journal: journal,
                   fiscal_year: fiscal_year,
                   entry_date: fiscal_year.start_date + 10,
                   project_id: project_id)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense_account,
           debit: BigDecimal("1000.00"), credit: BigDecimal("0"))
    create(:journal_entry_line, journal_entry: entry, account: liability_account,
           debit: BigDecimal("0"), credit: BigDecimal("1000.00"))
    entry.post!
    entry
  end

  describe "GET /accounting/reports/trial_balance" do
    it "retourne 200" do
      get accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id)
      expect(response).to have_http_status(:ok)
    end

    it "retourne 200 sans fiscal_year_id (utilise l'exercice ouvert)" do
      get accounting_reports_trial_balance_path
      expect(response).to have_http_status(:ok)
    end

    it "retourne 200 avec une date as_of invalide (rescue ArgumentError)" do
      get accounting_reports_trial_balance_path(
        fiscal_year_id: fiscal_year.id, as_of: "pas-une-date"
      )
      expect(response).to have_http_status(:ok)
    end

    it "retourne CSV avec ?format=csv" do
      create_posted_entry
      get accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id, format: :csv)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")
    end

    it "retourne XLSX avec ?format=xlsx" do
      create_posted_entry
      get accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id, format: :xlsx)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("spreadsheetml")
    end
  end

  describe "GET /accounting/reports/balance_sheet" do
    it "retourne 200" do
      get accounting_reports_balance_sheet_path(fiscal_year_id: fiscal_year.id)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/reports/income_statement" do
    it "retourne 200" do
      get accounting_reports_income_statement_path(fiscal_year_id: fiscal_year.id)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/reports/general_ledger" do
    it "retourne 200 avec un account_id" do
      get accounting_reports_general_ledger_path(
        fiscal_year_id: fiscal_year.id, account_id: expense_account.id
      )
      expect(response).to have_http_status(:ok)
    end

    it "retourne 200 sans account_id (formulaire vide)" do
      get accounting_reports_general_ledger_path(fiscal_year_id: fiscal_year.id)
      expect(response).to have_http_status(:ok)
    end

    it "retourne 200 avec une date invalide (rescue ArgumentError)" do
      get accounting_reports_general_ledger_path(
        fiscal_year_id: fiscal_year.id, date_from: "invalid"
      )
      expect(response).to have_http_status(:ok)
    end

    it "retourne CSV avec ?format=csv" do
      create_posted_entry
      get accounting_reports_general_ledger_path(
        fiscal_year_id: fiscal_year.id,
        account_id: expense_account.id,
        format: :csv
      )
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")
    end
  end

  describe "GET /accounting/reports/analytic_by_project" do
    before { create_posted_entry(project_id: 42) }

    it "retourne 200" do
      get accounting_reports_analytic_by_project_path(fiscal_year_id: fiscal_year.id)
      expect(response).to have_http_status(:ok)
    end

    it "retourne 200 filtré par project_id" do
      get accounting_reports_analytic_by_project_path(
        fiscal_year_id: fiscal_year.id, project_id: 42
      )
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/reports/analytic_by_axis" do
    let!(:axis) { create(:analytical_axis, :proj) }

    it "retourne 200 sans axis_id (formulaire vide)" do
      get accounting_reports_analytic_by_axis_path(fiscal_year_id: fiscal_year.id)
      expect(response).to have_http_status(:ok)
    end

    it "retourne 200 avec un axis_id" do
      get accounting_reports_analytic_by_axis_path(
        fiscal_year_id: fiscal_year.id, axis_id: axis.id
      )
      expect(response).to have_http_status(:ok)
    end

    it "retourne 200 avec un axis_id invalide (tableau vide)" do
      get accounting_reports_analytic_by_axis_path(
        fiscal_year_id: fiscal_year.id, axis_id: 0
      )
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/reports/analytic_cross" do
    let!(:proj_axis) { create(:analytical_axis, :proj) }
    let!(:act_axis)  { create(:analytical_axis, :act) }

    it "retourne 200 sans axes sélectionnés" do
      get accounting_reports_analytic_cross_path(fiscal_year_id: fiscal_year.id)
      expect(response).to have_http_status(:ok)
    end

    it "retourne 200 avec deux axes distincts" do
      get accounting_reports_analytic_cross_path(
        fiscal_year_id: fiscal_year.id,
        row_axis_id: proj_axis.id,
        col_axis_id: act_axis.id
      )
      expect(response).to have_http_status(:ok)
    end

    it "retourne 200 quand les deux axes sont identiques" do
      get accounting_reports_analytic_cross_path(
        fiscal_year_id: fiscal_year.id,
        row_axis_id: proj_axis.id,
        col_axis_id: proj_axis.id
      )
      expect(response).to have_http_status(:ok)
    end
  end
end
