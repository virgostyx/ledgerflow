# R20: closing bundle (ZIP of PDFs + manifest), full audit export (CSV/JSON) and filing data (JSON) of a
# fiscal year. Each download is recorded in the audit trail (R18).
class Accounting::ClosingBundlesController < ApplicationController
  before_action :set_fiscal_year

  def show
    authorize :closing_bundle, :show?, policy_class: Accounting::ClosingBundlePolicy
    @fiscal_years = Accounting::FiscalYear.order(start_date: :desc)
  end

  def bundle
    authorize :closing_bundle, :bundle?, policy_class: Accounting::ClosingBundlePolicy
    result = Accounting::ClosingBundle.call(fiscal_year: @fiscal_year, watermark: export_watermark)
    audit("closing_bundle", files: result.manifest[:files].size)
    send_data result.zip, filename: "closing_bundle_#{@fiscal_year.year}.zip", type: "application/zip"
  end

  def audit_export
    authorize :closing_bundle, :audit_export?, policy_class: Accounting::ClosingBundlePolicy
    audit("audit_export")
    send_data Accounting::AuditExport.call(fiscal_year: @fiscal_year), filename: "audit_export_#{@fiscal_year.year}.zip", type: "application/zip"
  end

  def filing_data
    authorize :closing_bundle, :filing_data?, policy_class: Accounting::ClosingBundlePolicy
    audit("filing_data")
    send_data JSON.pretty_generate(Accounting::FilingData.call(fiscal_year: @fiscal_year)), filename: "filing_data_#{@fiscal_year.year}.json", type: "application/json"
  end

  private

  def set_fiscal_year
    @fiscal_year = Accounting::FiscalYear.find_by(id: params[:fiscal_year_id]) || Accounting::FiscalYear.current || Accounting::FiscalYear.order(:start_date).last
    redirect_to accounting_root_path, alert: "No fiscal year." unless @fiscal_year
  end

  def audit(action, **payload)
    Accounting::AuditLog.record!(auditable: @fiscal_year, action: "export_#{action}", payload: payload.merge(year: @fiscal_year.year))
  end
end
