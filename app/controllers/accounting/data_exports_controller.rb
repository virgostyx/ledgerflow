# F13b: the standard data exports (streamed, each one recorded in the audit trail) and the full backup (built in the background, downloaded through
# a link that is signed and short-lived). Nothing is cached: these files hold the books.
class Accounting::DataExportsController < ApplicationController
  FORMATS = { "csv" => "text/csv; charset=utf-8", "json" => "application/json", "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }.freeze

  before_action { require_feature!(:f13) }

  def index
    authorize :data_export, :index?, policy_class: Accounting::DataExportPolicy
    @datasets = Exports::Standard::DATASETS.keys
    @backups = DataExport.where(kind: "backup").includes(:user).order(id: :desc).limit(20)
  end

  # GET /accounting/data_exports/file?dataset=entries&as=csv&from=&to=  (`as`, not `format`: the format of the request is another thing)
  def show
    authorize :data_export, :create?, policy_class: Accounting::DataExportPolicy
    format = params[:as].to_s
    return head(:not_found) unless FORMATS.key?(format)

    from, to = date_param(:from), date_param(:to)
    export = Exports::Standard.new(params[:dataset].to_s, from: from, to: to)
    Accounting::AuditLog.record!(auditable: ActsAsTenant.current_tenant, action: "data_export", user: current_user,
                                 payload: { dataset: export.dataset, format: format, from: from&.iso8601, to: to&.iso8601 })
    deliver(export, format)
  rescue ArgumentError => e
    redirect_to accounting_data_exports_path, alert: e.message
  rescue Exports::Standard::TooLarge => e
    redirect_to accounting_data_exports_path, alert: e.message
  end

  def backup
    authorize :data_export, :backup?, policy_class: Accounting::DataExportPolicy
    return redirect_to(accounting_data_exports_path, alert: "A backup is already being built.") if DataExport.where(kind: "backup", status: "processing").exists?

    export = DataExport.create!(user: current_user, kind: "backup")
    Accounting::AuditLog.record!(auditable: export, action: "backup_requested", user: current_user, payload: { data_export_id: export.id })
    Exports::BackupJob.perform_later(export.id)
    redirect_to accounting_data_exports_path, notice: "The backup is being built. This page shows when it is ready."
  end

  def download
    authorize :data_export, :backup?, policy_class: Accounting::DataExportPolicy
    export = DataExport.find_signed(params[:token], purpose: :data_export)
    return redirect_to(accounting_data_exports_path, alert: "This link has expired: use the new one on this page.") unless export&.ready? && export.entity_id == ActsAsTenant.current_tenant.id

    Accounting::AuditLog.record!(auditable: export, action: "backup_downloaded", user: current_user, payload: { data_export_id: export.id })
    send_data export.file.download, filename: export.file.filename.to_s, type: "application/zip", disposition: "attachment"
  end

  private

  def date_param(key) = params[key].present? ? Date.iso8601(params[key].to_s) : nil

  def deliver(export, format)
    filename = "#{export.dataset}-v#{Exports::Standard::SCHEMA_VERSION}.#{format}"
    response.headers["Cache-Control"] = "no-cache, no-store" # no-cache also keeps Rack::ETag from reading the whole body to hash it
    return send_data(export.xlsx, filename: filename, type: FORMATS.fetch(format), disposition: "attachment") if format == "xlsx"

    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: filename)
    response.headers["Content-Type"] = FORMATS.fetch(format)
    response.headers["X-Accel-Buffering"] = "no"
    self.response_body = export.public_send(format)
  end
end
