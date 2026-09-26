class Accounting::Settings::OpeningBalancesController < Accounting::Settings::BaseController
  TEMPLATES = {
    "balances" => "account_code,debit,credit\n",
    "invoices" => "type,partner_name,partner_vat,number,invoice_date,due_date,open_amount\n"
  }.freeze

  before_action :load_fiscal_year

  def show; end

  def create
    return refuse([ "Create the first fiscal year before importing opening balances" ]) unless @fiscal_year
    return refuse([ "Choose both files" ]) unless params[:balances_file] && params[:invoices_file]

    @import = params[:mode] == "import" ? :import : :check
    @result = Accounting::ImportOpeningBalances.call(
      fiscal_year: @fiscal_year, balances_csv: read(params[:balances_file]), invoices_csv: read(params[:invoices_file]),
      dry_run: @import == :check
    )
    return refuse(@result[:errors]) if @result.failure?

    render :show
  end

  def template
    send_data TEMPLATES.fetch(params[:kind]) { raise ActionController::RoutingError, "Not Found" },
              filename: "opening_#{params[:kind]}.csv", type: "text/csv"
  end

  private

  # The opening balances belong to the entity's first fiscal year.
  def load_fiscal_year
    @fiscal_year = Accounting::FiscalYear.order(:start_date).first
    @already_imported = @fiscal_year && Accounting::JournalEntry.where(
      fiscal_year: @fiscal_year, source_type: Accounting::JournalEntry::OPENING_SOURCE
    ).exists?
  end

  def read(upload) = upload.read.to_s.dup.force_encoding("UTF-8").delete_prefix("﻿")

  def refuse(errors)
    @errors = errors
    render :show, status: :unprocessable_content
  end
end
