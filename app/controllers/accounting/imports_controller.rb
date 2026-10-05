# F13a: the guided imports. Upload a file, map its columns (kept as a template if asked), check (a simulation that writes nothing), import, and
# take a batch back. Entries come in as drafts; nothing here validates.
class Accounting::ImportsController < ApplicationController
  MAX_BYTES = Integer(ENV.fetch("IMPORT_MAX_BYTES", 20.megabytes))

  before_action { require_feature!(:f13) }
  before_action :set_batch, only: %i[show update simulate run undo]

  def index
    authorize Accounting::ImportBatch
    @batches = Accounting::ImportBatch.guided.includes(:user).order(id: :desc).limit(100)
    @templates = ImportTemplate.order(:kind, :name)
  end

  def new
    authorize Accounting::ImportBatch, :create?
    @kind = Imports::Kind::KINDS.include?(params[:kind]) ? params[:kind] : "entries"
    @templates = ImportTemplate.where(kind: @kind).order(:name)
  end

  def create
    authorize Accounting::ImportBatch
    file = params[:file]
    return redirect_to(new_accounting_import_path(kind: params[:kind]), alert: "Choose a file.") unless file.respond_to?(:read)
    return redirect_to(new_accounting_import_path(kind: params[:kind]), alert: "The file is larger than #{MAX_BYTES / 1.megabyte} MB.") if file.size > MAX_BYTES

    batch = Imports::Start.call(user: current_user, kind: params[:kind], filename: file.original_filename, data: file.read,
                                template: ImportTemplate.find_by(id: params[:template_id], kind: params[:kind]), options: options_params)
    redirect_to accounting_import_path(batch), notice: "File read: #{batch.lines_read} rows. Map its columns, then check."
  rescue Imports::Reader::Unreadable => e
    redirect_to new_accounting_import_path(kind: params[:kind]), alert: e.message
  end

  def show
    authorize @batch
    @kind = Imports::Kind.for(@batch.kind)
    return unless @batch.result == "uploaded"

    table = Imports::Reader.read(@batch.queued_file.download, filename: @batch.filename)
    @headers, @sample = table.headers, table.rows.first(5)
  end

  def update
    authorize @batch
    return redirect_to(accounting_import_path(@batch), alert: "This batch was already run.") unless @batch.result == "uploaded"

    mapping = params.fetch(:mapping, {}).permit(*Imports::Kind.for(@batch.kind).fields.keys).to_h.compact_blank
    resolutions = params.fetch(:resolutions, {}).permit(accounts: {}, partners: {}).to_h.transform_values(&:compact_blank).compact_blank
    mapping["resolutions"] = resolutions if resolutions.any?
    @batch.update!(mapping: mapping, options: @batch.options.merge(options_params))
    save_template(mapping.except("resolutions"))
    redirect_to accounting_import_path(@batch), notice: "Mapping saved."
  end

  def simulate
    authorize @batch, :update?
    Imports::Run.call(batch: @batch, user: current_user, dry_run: true)
    redirect_to accounting_import_path(@batch), notice: "Simulation done: nothing was written."
  end

  def run
    authorize @batch, :create?
    return redirect_to(accounting_import_path(@batch), alert: "This batch was already run.") unless @batch.result == "uploaded"

    if @batch.lines_read > Imports::Run::BACKGROUND_ABOVE
      @batch.update_columns(result: "processing", lines_imported: 0)
      Imports::RunJob.perform_later(@batch.id, current_user.id)
      redirect_to accounting_import_path(@batch), notice: "The import runs in the background."
    else
      Imports::Run.call(batch: @batch, user: current_user)
      redirect_to accounting_import_path(@batch), notice: "Import done: #{@batch.summary['created']} created."
    end
  end

  def undo
    authorize @batch
    Imports::Undo.call(batch: @batch, user: current_user, reason: params[:reason].presence)
    redirect_to accounting_import_path(@batch), notice: "The batch was taken back."
  rescue Imports::Undo::Refused => e
    redirect_to accounting_import_path(@batch), alert: e.message
  end

  private

  def set_batch = @batch = Accounting::ImportBatch.guided.find(params[:id])

  def options_params = params.permit(:date_format, :decimal).to_h.select { |k, v| v.present? && (k != "date_format" || Imports::Kind::DATE_FORMATS.key?(v)) && (k != "decimal" || [ ".", "," ].include?(v)) }

  def save_template(mapping)
    return if params[:template_name].blank?

    template = ImportTemplate.find_or_initialize_by(kind: @batch.kind, name: params[:template_name].to_s.strip)
    template.update!(mapping: mapping, options: @batch.options)
  end
end
