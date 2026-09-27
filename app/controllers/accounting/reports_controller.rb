class Accounting::ReportsController < ApplicationController
  before_action :set_fiscal_year

  # R01 (docs/dev/reports/spec.md §5): ouverture/mouvements/clôture, comparatif N-1,
  # drill-down vers le grand livre, exports via le socle Reports::* (§2.1/§14).
  def trial_balance
    authorize :report, :trial_balance?, policy_class: Accounting::ReportPolicy

    @as_of = parse_date(params[:as_of], @fiscal_year.end_date)
    filters = Reports::Filters.new(fiscal_year_id: @fiscal_year.id, date_to: @as_of,
                                    comparative: params[:comparative])
    @result = Accounting::TrialBalanceReport.new(filters: filters).call
    @rows   = @result.rows # kept for any other view still reading it directly

    respond_to do |format|
      format.html
      format.csv  { send_data Reports::Exporters::Csv.call(@result, columns: trial_balance_export_columns),
                              filename: "balance_#{@fiscal_year.year}.csv", type: "text/csv; charset=utf-8" }
      format.xlsx { send_data Reports::Exporters::Xlsx.call(@result, columns: trial_balance_export_columns, title: "Trial balance"),
                              filename: "balance_#{@fiscal_year.year}.xlsx",
                              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }
      format.pdf  { send_data Reports::Exporters::Pdf.call(@result, columns: trial_balance_export_columns, title: "Trial balance"),
                              filename: "balance_#{@fiscal_year.year}.pdf", type: "application/pdf" }
    end
  rescue ArgumentError
    @as_of  = @fiscal_year.end_date
    @result = Reports::Result.new(rows: [])
    @rows   = []
    render :trial_balance
  end

  def balance_sheet
    authorize :report, :balance_sheet?, policy_class: Accounting::ReportPolicy

    @as_of  = @fiscal_year.end_date
    all_rows = Accounting::TrialBalanceQuery.new(fiscal_year: @fiscal_year, as_of: @as_of).call
    @rows   = all_rows.reject { |r| r.account_type.in?(%w[expense revenue]) }
  end

  def income_statement
    authorize :report, :income_statement?, policy_class: Accounting::ReportPolicy

    @as_of  = @fiscal_year.end_date
    all_rows = Accounting::TrialBalanceQuery.new(fiscal_year: @fiscal_year, as_of: @as_of).call
    @rows   = all_rows.select { |r| r.account_type.in?(%w[expense revenue]) }
  end

  def annual_accounts
    authorize :report, :annual_accounts?, policy_class: Accounting::ReportPolicy

    @report = Accounting::AnnualAccounts.new(fiscal_year: @fiscal_year).call

    respond_to do |format|
      format.html
      format.xlsx { render xlsx: "annual_accounts", filename: "annual_accounts_#{@fiscal_year.year}.xlsx" }
    end
  end

  # R02 (docs/dev/reports/spec.md §6): solde d'ouverture ("Report"), tiers/journal/
  # lettrage en filtres, drill-down par tiers vers le grand livre auxiliaire.
  def general_ledger
    authorize :report, :general_ledger?, policy_class: Accounting::ReportPolicy

    @accounts = Accounting::Account.active.order(:code)
    @account  = Accounting::Account.find_by(id: params[:account_id])
    @partner  = Accounting::Partner.find_by(id: params[:partner_id])
    @journal_filter = Accounting::Journal.find_by(id: params[:journal_id])
    @date_from = parse_date(params[:date_from], @fiscal_year.start_date)
    @date_to   = parse_date(params[:date_to],   @fiscal_year.end_date)

    if @account
      @query = Accounting::GeneralLedgerQuery.new(
        account: @account, fiscal_year: @fiscal_year,
        date_from: @date_from, date_to: @date_to,
        partner: @partner, journal: @journal_filter,
        lettering: params[:lettering]&.to_sym
      )
      @rows = @query.call
    else
      @rows = []
    end

    respond_to do |format|
      format.html
      format.csv do
        send_data Reports::Exporters::Csv.call(general_ledger_result, columns: general_ledger_export_columns),
                  filename: "grand_livre_#{@account&.code}_#{@fiscal_year.year}.csv",
                  type: "text/csv; charset=utf-8"
      end
    end
  rescue ArgumentError
    @rows = []
    render :general_ledger
  end

  def journal_summary
    authorize :report, :general_ledger?, policy_class: Accounting::ReportPolicy

    @rows = Accounting::JournalSummaryQuery.new(fiscal_year: @fiscal_year).call
    @gaps = Accounting::Journal.active.each_with_object({}) do |journal, memo|
      gaps = Accounting::JournalNumberingGaps.new(journal: journal, fiscal_year: @fiscal_year).call
      memo[journal.id] = gaps if gaps.any?
    end
  end

  def aged_balance
    authorize :report, :aged_balance?, policy_class: Accounting::ReportPolicy

    @kind  = params[:kind] == "supplier" ? :supplier : :customer
    @as_of = begin
      parse_date(params[:as_of], Date.current)
    rescue ArgumentError
      Date.current
    end
    @rows   = Accounting::AgedBalanceQuery.new(kind: @kind, as_of: @as_of).call
    @totals = Accounting::AgedBalanceQuery.totals(@rows)

    @stale_days    = params[:stale_days].presence&.to_i || 90
    @stale_credits = Accounting::StaleCreditsQuery.new(kind: @kind, as_of: @as_of, min_age_days: @stale_days).call

    respond_to do |format|
      format.html
      format.csv { send_data aged_balance_csv, filename: "aged_balance_#{@kind}_#{@as_of}.csv",
                              type: "text/csv; charset=utf-8" }
    end
  end

  # R05 (docs/dev/reports/spec.md §7): lignes ouvertes non lettrées, ligne par ligne,
  # + groupes équilibrés laissés sans lettrage.
  def unlettered_lines
    authorize :report, :unlettered_lines?, policy_class: Accounting::ReportPolicy

    @kind = %w[customer supplier both].include?(params[:kind]) ? params[:kind].to_sym : :both
    @as_of = begin
      parse_date(params[:as_of], Date.current)
    rescue ArgumentError
      Date.current
    end
    @min_age_days = params[:min_age_days].presence&.to_i

    query  = Accounting::UnletteredLinesQuery.new(kind: @kind, as_of: @as_of, min_age_days: @min_age_days)
    @rows  = query.call
    @balanced_groups = query.balanced_unlettered_groups
  end

  # R06 (docs/dev/reports/spec.md §8): B + BN − SN = A. "Figer" enregistre le résultat
  # dans accounting_bank_reconciliation_reports (Accounting::BankReconciliationReport,
  # construit au socle), immuable.
  def bank_reconciliation_report
    authorize :report, :bank_reconciliation_report?, policy_class: Accounting::ReportPolicy

    @bank_accounts = Accounting::BankAccount.where(active: true).order(:label_fr)
    @bank_account  = Accounting::BankAccount.find_by(id: params[:bank_account_id]) || @bank_accounts.first
    @as_of = begin
      parse_date(params[:as_of], Date.current)
    rescue ArgumentError
      Date.current
    end

    @result = Accounting::BankReconciliationQuery.new(bank_account: @bank_account, as_of: @as_of).call if @bank_account
    @frozen_reports = @bank_account ? @bank_account.bank_reconciliation_reports.order(as_of: :desc) : []
  end

  def freeze_bank_reconciliation_report
    authorize :report, :bank_reconciliation_report?, policy_class: Accounting::ReportPolicy

    bank_account = Accounting::BankAccount.find(params[:bank_account_id])
    as_of  = parse_date(params[:as_of], Date.current)
    result = Accounting::BankReconciliationQuery.new(bank_account: bank_account, as_of: as_of).call

    Accounting::BankReconciliationReport.record!(
      bank_account: bank_account, as_of: as_of, user: current_user,
      result: {
        statement_balance: result.statement_balance.to_s, accounting_balance: result.accounting_balance.to_s,
        bn_total: result.bn_total.to_s, sn_total: result.sn_total.to_s,
        expected_balance: result.expected_balance.to_s, gap: result.gap.to_s,
        bn: result.bn.map { |i| { date: i.date.to_s, label: i.label, amount: i.amount.to_s } },
        sn: result.sn.map { |i| { date: i.date.to_s, label: i.label, amount: i.amount.to_s } }
      }
    )

    redirect_to accounting_reports_bank_reconciliation_report_path(bank_account_id: bank_account.id, as_of: as_of),
                notice: "Reconciliation frozen for #{as_of}."
  end

  def analytic_by_project
    authorize :report, :analytic_by_project?, policy_class: Accounting::ReportPolicy

    @project_id = params[:project_id].present? ? params[:project_id].to_i : nil
    @rows = Accounting::AnalyticProjectQuery.new(
      fiscal_year: @fiscal_year, project_id: @project_id
    ).call
  end

  def analytic_by_axis
    authorize :report, :analytic_by_axis?, policy_class: Accounting::ReportPolicy

    @axes = Accounting::AnalyticalAxis.active.ordered
    @axis = Accounting::AnalyticalAxis.find_by(id: params[:axis_id])
    @rows = @axis ? Accounting::AnalyticByAxisQuery.new(fiscal_year: @fiscal_year, axis: @axis).call : []
  end

  def analytic_cross
    authorize :report, :analytic_cross?, policy_class: Accounting::ReportPolicy

    @axes     = Accounting::AnalyticalAxis.active.ordered
    @row_axis = Accounting::AnalyticalAxis.find_by(id: params[:row_axis_id])
    @col_axis = Accounting::AnalyticalAxis.find_by(id: params[:col_axis_id])

    if @row_axis && @col_axis && @row_axis != @col_axis
      raw_results  = Accounting::AnalyticCrossQuery.new(
        fiscal_year: @fiscal_year, row_axis: @row_axis, col_axis: @col_axis
      ).call
      @row_accounts = raw_results.map(&:row_account).uniq.sort_by(&:code)
      @col_accounts = raw_results.map(&:col_account).uniq.sort_by(&:code)
      @matrix       = raw_results.index_by { |r| [ r.row_account.id, r.col_account.id ] }
    else
      @row_accounts = []
      @col_accounts = []
      @matrix       = {}
    end
  end

  private

  def set_fiscal_year
    @fiscal_year = if params[:fiscal_year_id].present?
      Accounting::FiscalYear.find(params[:fiscal_year_id])
    else
      Accounting::FiscalYear.current
    end
  end

  # Raises ArgumentError on an invalid date (rescued by trial_balance).
  def parse_date(value, default)
    value.present? ? Date.parse(value) : default
  end

  helper_method :trial_balance_view_columns

  # Same columns as the exports, plus the account-code drill-down link
  # (docs/dev/reports/spec.md §5: "Clic sur un compte: R02... même période et mêmes filtres").
  def trial_balance_view_columns
    trial_balance_columns.map do |column|
      next column unless column[:key] == :code

      column.merge(link: ->(row) {
        accounting_reports_general_ledger_path(fiscal_year_id: @fiscal_year.id, account_id: account_id_for(row))
      })
    end
  end

  def account_id_for(row)
    row.respond_to?(:row) ? row.row.id : row.id
  end

  # Reports::Exporters::* expect [label, key_or_proc] tuples, not the {key:, label:}
  # hashes Reports::TableComponent takes — same columns, adapted to each contract.
  def trial_balance_export_columns
    trial_balance_columns.map { |column| [ column[:label], column[:key] ] }
  end

  def trial_balance_columns
    columns = [
      { key: :code, label: "Code" },
      { key: :label_fr, label: "Label" },
      { key: :opening_display_debit, label: "Opening Debit" },
      { key: :opening_display_credit, label: "Opening Credit" },
      { key: :movement_debit, label: "Movement Debit" },
      { key: :movement_credit, label: "Movement Credit" },
      { key: :closing_display_debit, label: "Closing Debit" },
      { key: :closing_display_credit, label: "Closing Credit" }
    ]
    return columns unless params[:comparative].present?

    columns + [
      { key: :comparative_closing, label: "Closing N-1" },
      { key: :variation_amount, label: "Variation" }
    ]
  end

  AGED_BALANCE_CSV_COLUMNS = (Accounting::AgedBalanceQuery::BUCKETS + %i[unallocated total overdue]).freeze

  def aged_balance_csv
    require "csv"
    t = ->(key) { I18n.t("accounting.reports.aged_balance.#{key}") }
    "\uFEFF" + CSV.generate(headers: true) do |csv|
      csv << [ t.(:partner), *AGED_BALANCE_CSV_COLUMNS.map { |b| t.(b) }, t.(:overdue_pct) ]
      @rows.each do |row|
        csv << [ row.partner_name || t.(:no_partner),
                *AGED_BALANCE_CSV_COLUMNS.map { |col| format("%.2f", row.public_send(col)) },
                row.overdue_pct.nil? ? "" : format("%.1f", row.overdue_pct) ]
      end
      csv << [ I18n.t("accounting.reports.totals"),
              *AGED_BALANCE_CSV_COLUMNS.map { |col| format("%.2f", @totals.public_send(col)) },
              @totals.overdue_pct.nil? ? "" : format("%.1f", @totals.overdue_pct) ]
    end
  end

  def trial_balance_csv
    require "csv"
    CSV.generate(headers: true) do |csv|
      csv << [
        I18n.t("accounting.reports.csv.code"),
        I18n.t("accounting.reports.csv.label"),
        I18n.t("accounting.reports.csv.debit"),
        I18n.t("accounting.reports.csv.credit"),
        I18n.t("accounting.reports.csv.balance")
      ]
      @rows.each do |row|
        csv << [ row.code, row.label_fr,
                format("%.2f", row.total_debit),
                format("%.2f", row.total_credit),
                format("%.2f", row.balance) ]
      end
    end
  end

  def general_ledger_result
    Reports::Result.new(rows: @rows, currency: "EUR")
  end

  def general_ledger_export_columns
    [
      [ "Date", :entry_date ], [ "Reference", :reference ], [ "Label", :label ],
      [ "Partner", :partner_name ], [ "Debit", :debit ], [ "Credit", :credit ],
      [ "Running balance", :running_balance ], [ "Lettering", :lettering_code ]
    ]
  end
end
