class Accounting::ReportsController < ApplicationController
  before_action :set_fiscal_year

  def trial_balance
    authorize :report, :trial_balance?, policy_class: Accounting::ReportPolicy

    as_of   = params[:as_of].present? ? Date.parse(params[:as_of]) : nil
    @as_of  = as_of || @fiscal_year.end_date
    @rows   = Accounting::TrialBalanceQuery.new(fiscal_year: @fiscal_year, as_of: @as_of).call

    respond_to do |format|
      format.html
      format.csv  { send_data trial_balance_csv, filename: "balance_#{@fiscal_year.year}.csv",
                               type: "text/csv; charset=utf-8" }
      format.xlsx { render xlsx: "trial_balance", filename: "balance_#{@fiscal_year.year}.xlsx" }
    end
  rescue ArgumentError
    @rows  = []
    @as_of = @fiscal_year.end_date
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

  def general_ledger
    authorize :report, :general_ledger?, policy_class: Accounting::ReportPolicy

    @accounts = Accounting::Account.active.order(:code)
    @account  = Accounting::Account.find_by(id: params[:account_id])
    @date_from = params[:date_from].present? ? Date.parse(params[:date_from]) : @fiscal_year.start_date
    @date_to   = params[:date_to].present?   ? Date.parse(params[:date_to])   : @fiscal_year.end_date

    if @account
      @rows = Accounting::GeneralLedgerQuery.new(
        account: @account, fiscal_year: @fiscal_year,
        date_from: @date_from, date_to: @date_to
      ).call
    else
      @rows = []
    end

    respond_to do |format|
      format.html
      format.csv do
        send_data general_ledger_csv,
                  filename: "grand_livre_#{@account&.code}_#{@fiscal_year.year}.csv",
                  type: "text/csv; charset=utf-8"
      end
    end
  rescue ArgumentError
    @rows = []
    render :general_ledger
  end

  def analytic_by_project
    authorize :report, :analytic_by_project?, policy_class: Accounting::ReportPolicy

    @project_id = params[:project_id].present? ? params[:project_id].to_i : nil
    @rows = Accounting::AnalyticProjectQuery.new(
      fiscal_year: @fiscal_year, project_id: @project_id
    ).call
  end

  private

  def set_fiscal_year
    @fiscal_year = if params[:fiscal_year_id].present?
                     Accounting::FiscalYear.find(params[:fiscal_year_id])
    else
                     Accounting::FiscalYear.find_by(status: :open)
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

  def general_ledger_csv
    require "csv"
    CSV.generate(headers: true) do |csv|
      csv << [
        I18n.t("accounting.reports.csv.date"),
        I18n.t("accounting.reports.csv.reference"),
        I18n.t("accounting.reports.csv.label"),
        I18n.t("accounting.reports.csv.debit"),
        I18n.t("accounting.reports.csv.credit"),
        I18n.t("accounting.reports.csv.running_balance")
      ]
      @rows.each do |row|
        csv << [ row.entry_date, row.reference, row.label,
                format("%.2f", row.debit),
                format("%.2f", row.credit),
                format("%.2f", row.running_balance) ]
      end
    end
  end
end
