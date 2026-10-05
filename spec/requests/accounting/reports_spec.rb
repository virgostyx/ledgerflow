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

    it "adds the currency and the balance in currency of the accounts kept in one, on screen and in the CSV, and only then (F11)" do
      create_posted_entry
      get accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id)
      expect(response.body).not_to include("Balance in currency")

      held = create(:account, code: "467001", account_type: :asset, normal_balance: :debit, account_class: 4, currency: "USD")
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 2)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: held, debit: BigDecimal("909.09"), credit: 0, currency: "USD", amount_currency: BigDecimal("1000"), exchange_rate: BigDecimal("1.1"))
      create(:journal_entry_line, journal_entry: entry, account: create(:account, code: "440998", account_type: :liability, normal_balance: :credit), debit: 0, credit: BigDecimal("909.09"))
      entry.post!

      get accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id)
      expect(response.body).to include("Balance in currency", "USD")
      get accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id, format: :csv)
      expect(response.body).to include("Currency", "Balance in currency", "USD")
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

    it "shows the opening/movement/closing breakdown (§5) and a drill-down link to the general ledger" do
      create_posted_entry
      get accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id)

      expect(response.body).to include("Opening", "Movement", "Closing")
      expect(response.body).to match(%r{href="[^"]*general_ledger\?[^"]*account_id=#{expense_account.id}[^"]*"})
    end

    it "adds the prior year's closing balance and variation when comparative=previous_year" do
      previous_fy = create(:fiscal_year, entity: entity, year: fiscal_year.year - 1, status: :closed,
                            start_date: fiscal_year.start_date.prev_year, end_date: fiscal_year.end_date.prev_year)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: previous_fy,
                     entry_date: previous_fy.start_date + 1)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: 400, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: liability_account, debit: 0, credit: 400)
      entry.post!
      create_posted_entry

      get accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id, comparative: "previous_year")

      expect(response.body).to include("Variation")
      expect(response.body).to include("400")
    end

    it "returns CSV via the new Reports::Exporters::Csv (BOM + comma decimal in the default en locale)" do
      create_posted_entry
      get accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id, format: :csv)

      expect(response.body.b).to start_with("\xEF\xBB\xBF".b)
      expect(response.body).to include("1000.00")
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

    it "retourne 200 avec un compte ET une date invalide (le rescue ne doit pas planter sur @query)" do
      get accounting_reports_general_ledger_path(
        fiscal_year_id: fiscal_year.id, account_id: expense_account.id, date_from: "invalid"
      )
      expect(response).to have_http_status(:ok)
    end

    it "shows the currency, the amount in currency and the rate of a foreign line, and the same columns in the CSV (F11)" do
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 3)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: BigDecimal("909.09"), credit: 0, currency: "USD",
             amount_currency: BigDecimal("1000"), exchange_rate: BigDecimal("1.1"))
      create(:journal_entry_line, journal_entry: entry, account: create(:account, code: "440999", account_type: :liability, normal_balance: :credit),
             debit: 0, credit: BigDecimal("909.09"))
      entry.post!

      get accounting_reports_general_ledger_path(fiscal_year_id: fiscal_year.id, account_id: expense_account.id)
      expect(response.body).to include("Amount in currency", "1000.00 USD", "1.1")

      get accounting_reports_general_ledger_path(fiscal_year_id: fiscal_year.id, account_id: expense_account.id, format: :csv)
      expect(response.body).to include("Currency", "Amount in currency", "Rate", "USD", "1000.0")
    end

    it "does not show the currency columns when every line is in EUR" do
      create_posted_entry
      get accounting_reports_general_ledger_path(fiscal_year_id: fiscal_year.id, account_id: expense_account.id)
      expect(response.body).not_to include("Amount in currency")
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

    it "shows the opening balance (Report) and closing balance section rows" do
      create_posted_entry
      get accounting_reports_general_ledger_path(fiscal_year_id: fiscal_year.id, account_id: expense_account.id,
                                                    date_from: fiscal_year.start_date + 15)
      expect(response.body).to include("Report", "Closing balance")
    end

    it "narrows to one partner and links a partner's lines to their auxiliary ledger" do
      alice = create(:partner, name: "Alice")
      create_posted_entry # no partner
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                     entry_date: fiscal_year.start_date + 11)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: expense_account, partner: alice, debit: 50, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: liability_account, debit: 0, credit: 50)
      entry.post!

      get accounting_reports_general_ledger_path(fiscal_year_id: fiscal_year.id, account_id: expense_account.id,
                                                    partner_id: alice.id)
      expect(response.body).to include("Alice")
      expect(response.body).to match(%r{href="[^"]*general_ledger\?[^"]*partner_id=#{alice.id}[^"]*"})
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

  describe "GET /accounting/reports/aged_balance" do
    it "returns 200 for customers by default" do
      get accounting_reports_aged_balance_path
      expect(response).to have_http_status(:ok)
    end

    it "returns 200 for suppliers and lists open partner balances" do
      partner = create(:partner, :supplier, name: "Acme Supplies")
      supplier_account = create(:account, :supplier, reconcilable: true)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: BigDecimal("50"), credit: BigDecimal("0"))
      create(:journal_entry_line, journal_entry: entry, account: supplier_account, partner: partner,
             debit: BigDecimal("0"), credit: BigDecimal("50"))
      entry.post!

      get accounting_reports_aged_balance_path(kind: "supplier", as_of: Date.current)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Supplies")
    end

    it "lets a customer row start a task about the partner, show its tasks, and leads to the reminders (P2 exit criterion)" do
      customer_account = create(:account, :customer, reconcilable: true)
      partner = create(:partner, name: "Late Payer", payment_terms_days: 0)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current - 40)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: partner, debit: BigDecimal("100"), credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: 0, credit: BigDecimal("100"))
      entry.post!

      get accounting_reports_aged_balance_path
      expect(response.body).to include(ERB::Util.h(new_accounting_task_path(target_type: "Accounting::Partner", target_id: partner.id))).and include(accounting_dunning_runs_path)
      expect(response.body).not_to include("1 task")

      Accounting::Task.create!(title: "Call them", target: partner)
      get accounting_reports_aged_balance_path
      expect(response.body).to include(ERB::Util.h(accounting_tasks_path(scope: "all", target_type: "Accounting::Partner", target_id: partner.id)))
    end

    it "groups the open balances by currency, with their value at the closing rate when asked (F11)" do
      customer_account = create(:account, :customer, reconcilable: true)
      partner = create(:partner, name: "Acme Ltd", payment_terms_days: 0)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current - 3)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: partner, debit: BigDecimal("909.09"), credit: 0, currency: "USD",
             amount_currency: BigDecimal("1000"), exchange_rate: BigDecimal("1.1"))
      create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: 0, credit: BigDecimal("909.09"), currency: "USD",
             amount_currency: BigDecimal("-1000"), exchange_rate: BigDecimal("1.1"))
      entry.post!
      Accounting::ExchangeRate.create!(currency: "USD", rate_date: Date.current, rate: "1.25", rate_type: :closing, source: "manual")

      get accounting_reports_aged_balance_path(by_currency: 1)
      expect(response.body).to include('data-section="by-currency"', "USD", "Acme Ltd", "1000.00")
      expect(response.body).not_to include("Closing rate (per 1 EUR)")

      get accounting_reports_aged_balance_path(by_currency: 1, at_closing_rate: 1)
      expect(response.body).to include("1.25", "800.00")
    end

    it "does not show the currency table unless asked" do
      get accounting_reports_aged_balance_path
      expect(response.body).not_to include('data-section="by-currency"')
    end

    it "falls back to customers on an unknown kind" do
      get accounting_reports_aged_balance_path(kind: "bogus")
      expect(response).to have_http_status(:ok)
    end

    it "returns 200 with an invalid as_of date" do
      get accounting_reports_aged_balance_path(as_of: "not-a-date")
      expect(response).to have_http_status(:ok)
    end

    it "returns CSV with ?format=csv, BOM-prefixed and one row per partner plus totals" do
      partner = create(:partner, name: "Acme Supplies")
      customer_account = create(:account, :customer, reconcilable: true)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: BigDecimal("100"), credit: BigDecimal("0"))
      create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: partner,
             debit: BigDecimal("100"), credit: BigDecimal("0"))
      entry.post!

      get accounting_reports_aged_balance_path(as_of: Date.current, format: :csv)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to start_with("\uFEFF")
      body = response.body.delete_prefix("\uFEFF")
      rows = CSV.parse(body, headers: true).map(&:to_h)
      expect(rows.map { |r| r["Partner"] }).to eq([ "Acme Supplies", "Totals" ])
      expect(rows.last["Total"]).to eq("100.00")
    end

    it "shows unallocated credits older than the threshold, and honors a custom stale_days" do
      partner = create(:partner, name: "Old Credit Co")
      customer_account = create(:account, :customer, reconcilable: true)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current - 95)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: BigDecimal("0"), credit: BigDecimal("40"))
      create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: partner,
             debit: BigDecimal("0"), credit: BigDecimal("40"))
      entry.post!

      get accounting_reports_aged_balance_path
      expect(response.body).to include(I18n.t("accounting.reports.aged_balance.stale_title", days: 90))
      html = response.body.gsub(/data-chart-option-value="[^"]*"/, "") # the chart JSON also carries partner names
      expect(html.scan("Old Credit Co").size).to eq(2) # main table + stale section

      get accounting_reports_aged_balance_path(stale_days: 100)
      expect(response.body).not_to include(I18n.t("accounting.reports.aged_balance.stale_title", days: 100))
      html = response.body.gsub(/data-chart-option-value="[^"]*"/, "")
      expect(html.scan("Old Credit Co").size).to eq(1) # main table only
    end

    it "redirects a user without report access (no access to the entity)" do
      sign_out accountant
      budget_user = create(:user, role: :budget_user)
      sign_in budget_user

      get accounting_reports_aged_balance_path
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET /accounting/reports/annual_customer_listing" do
    it "renders the listing" do
      get accounting_reports_annual_customer_listing_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Annual customer listing")
    end

    it "exports CSV" do
      get accounting_reports_annual_customer_listing_path(format: :csv)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to start_with("vat_number,name")
    end
  end

  describe "R12 analytic pivot and margin" do
    let!(:axis) { create(:analytical_axis, :proj) }
    let!(:alpha) { create(:analytical_account, analytical_axis: axis, code: "PRJ-A") }

    it "renders the pivot by analytical account and by month" do
      get accounting_reports_analytic_pivot_path(axis_id: axis.id)
      expect(response).to have_http_status(:ok)
      get accounting_reports_analytic_pivot_path(axis_id: axis.id, columns: "month")
      expect(response).to have_http_status(:ok)
    end

    it "renders the margin report with both allocation keys" do
      create_posted_entry
      %w[revenue direct_costs].each do |key|
        get accounting_reports_analytic_margin_path(axis_id: axis.id, allocation_key: key)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "R14 cash forecast" do
    it "renders the forecast with its chart and the items form" do
      get accounting_reports_cash_forecast_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="chart"', "Manual and recurring items")
    end

    it "accepts the 6-month horizon and a scenario" do
      get accounting_reports_cash_forecast_path(horizon: "months_6", scenario: "prudent", threshold: "500")
      expect(response).to have_http_status(:ok)
    end

    it "adds and removes a manual item" do
      expect do
        post accounting_cash_forecast_items_path, params: { accounting_cash_forecast_item: { label: "Rent", direction: "outflow", amount: "800", recurrence: "monthly", first_date: Date.current.to_s } }
      end.to change(Accounting::CashForecastItem, :count).by(1)
      expect { delete accounting_cash_forecast_item_path(Accounting::CashForecastItem.last) }.to change(Accounting::CashForecastItem, :count).by(-1)
    end

    it "rejects an invalid item with a message" do
      post accounting_cash_forecast_items_path, params: { accounting_cash_forecast_item: { label: "", amount: "0", first_date: Date.current.to_s } }
      expect(flash[:alert]).to be_present
    end
  end

  describe "R15 cash flow" do
    it "renders both methods and the waterfall" do
      create_posted_entry
      %w[indirect direct].each do |m|
        get accounting_reports_cash_flow_path(method_view: m)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-controller="chart"', "Check (I9)")
      end
    end

    it "exports an XLSX workbook with an Indirect and a Direct sheet" do
      get accounting_reports_cash_flow_path(format: :xlsx)
      expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      workbook = Zip::File.open_buffer(StringIO.new(response.body)).find_entry("xl/workbook.xml").get_input_stream.read
      sheets = workbook
      expect(sheets).to include('name="Indirect"', 'name="Direct"')
    end
  end

  describe "R16 fixed-asset movements" do
    it "renders the empty state and, with an asset, the movements and checks" do
      get accounting_reports_fixed_asset_movements_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No fixed assets recorded.", "Register vs ledger")

      create(:fixed_asset, :depreciable, acquisition_date: fiscal_year.start_date + 1, in_service_date: fiscal_year.start_date + 1)
      get accounting_reports_fixed_asset_movements_path
      expect(response.body).to include("Furniture and vehicles")
    end
  end
end
