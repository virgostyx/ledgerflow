# F03: the document store. Files are served through this controller only (signed-in, tied to the entity and to
# the right), never by a public address. A viewing is not audited; a download, an archiving and a deletion are.
class Accounting::DocumentsController < ApplicationController
  before_action { require_feature!(:f03) }
  before_action :set_document, only: %i[show update destroy file download archive]

  # What a browser may show in the page: nothing that can carry markup or script.
  INLINE_TYPES = %w[application/pdf image/png image/jpeg].freeze

  def index
    authorize Accounting::Document
    documents = Accounting::Document.includes(:uploaded_by).order(created_at: :desc, id: :desc)
    documents = case params[:status]
    when "inbox", "linked", "archived" then documents.where(status: params[:status])
    else documents.where.not(status: :archived)
    end
    documents = documents.where(kind: params[:kind]) if Accounting::Document.kinds.key?(params[:kind])
    documents = documents.where("name ILIKE ?", "%#{Accounting::Document.sanitize_sql_like(params[:q].to_s.strip)}%") if params[:q].present?
    @pagy, @documents = pagy(documents)
  end

  def create
    authorize Accounting::Document
    files = Array(params[:files]).select { |file| file.respond_to?(:original_filename) }
    return redirect_to(accounting_documents_path, alert: t("documents.choose_file")) if files.empty?

    kind = Accounting::Document.kinds.key?(params[:kind]) ? params[:kind] : nil
    results = files.map { |file| [ file.original_filename, Accounting::UploadDocument.call(io: file, filename: file.original_filename, user: current_user, kind: kind) ] }
    refused = results.select { |_, result| result.failure? }
    flash[:notice] = t("documents.uploaded", count: results.size - refused.size) if refused.size < results.size
    flash[:alert]  = refused.map { |name, result| "#{name}: #{result.message}" }.join(" ") if refused.any?
    redirect_to accounting_documents_path
  end

  def show
    authorize @document
    @links = @document.links.includes(:target)
  end

  def update
    authorize @document
    if Accounting::Document.kinds.key?(params[:kind]) && @document.update(kind: params[:kind])
      redirect_to accounting_document_path(@document), notice: t("documents.updated")
    else
      redirect_to accounting_document_path(@document), alert: t("documents.errors.evidence")
    end
  rescue Accounting::ImmutableRecordError
    redirect_to accounting_document_path(@document), alert: t("documents.errors.evidence")
  end

  # Shown in the page (viewer) when the type is safe to show; every other type is a download.
  def file
    authorize @document, :show?
    send_file_data(inline: INLINE_TYPES.include?(@document.content_type))
  end

  def download
    authorize @document
    Accounting::AuditLog.record!(auditable: @document, action: "document_download", payload: { name: @document.name, sha256: @document.sha256 })
    send_file_data(inline: false)
  end

  def archive
    authorize @document
    @document.update!(status: :archived)
    Accounting::AuditLog.record!(auditable: @document, action: "document_archive", payload: { name: @document.name })
    redirect_to accounting_documents_path, notice: t("documents.archived")
  end

  # Only after the retention term, never under a legal hold, and only for those who hold documents.delete_expired.
  def destroy
    authorize @document
    if @document.destroy
      Accounting::AuditLog.record!(auditable: @document, action: "document_delete", payload: { name: @document.name, sha256: @document.sha256 })
      redirect_to accounting_documents_path, notice: t("documents.deleted")
    else
      redirect_to accounting_document_path(@document), alert: @document.errors.full_messages.to_sentence
    end
  end

  private

  def set_document = @document = Accounting::Document.find(params[:id])

  def send_file_data(inline:)
    response.set_header("X-Content-Type-Options", "nosniff")
    response.set_header("Content-Security-Policy", "default-src 'none'") unless inline
    send_data @document.file.download, type: @document.content_type, filename: @document.name, disposition: inline ? "inline" : "attachment"
  end
end
