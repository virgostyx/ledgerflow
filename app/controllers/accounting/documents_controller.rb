# F03: the document store. Files are served through this controller only (signed-in, tied to the entity and to
# the right), never by a public address. A viewing is not audited; a download, an archiving and a deletion are.
class Accounting::DocumentsController < ApplicationController
  before_action { require_feature!(:f03) }
  before_action :set_document, only: %i[show update destroy file download archive confirm_field rerun create_invoice split legal_hold]

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
    documents = documents.where(origin: params[:origin]) if Accounting::Document.origins.key?(params[:origin])
    documents = documents.search(params[:q]) if params[:q].present?
    documents = documents.for_partner(params[:partner_id].to_i) if params[:partner_id].to_s.match?(/\A\d+\z/)
    documents = documents.dated(date_param(:from), date_param(:to))
    documents = documents.amount_between(amount_param(:min_amount), amount_param(:max_amount))
    @suppliers = Accounting::Partner.where(partner_type: %i[supplier both]).order(:name)
    @pagy, @documents = pagy(documents)
  end

  def create
    authorize Accounting::Document
    files = Array(params[:files]).select { |file| file.respond_to?(:original_filename) }
    return redirect_to(accounting_documents_path, alert: t("documents.choose_file")) if files.empty?

    kind = Accounting::Document.kinds.key?(params[:kind]) ? params[:kind] : nil
    result = Accounting::UploadFiles.call(files: files.map { |file| [ file, file.original_filename ] }, user: current_user, kind: kind)
    flash[:notice] = t("documents.uploaded", count: result.created.size) if result.created.any?
    flash[:alert]  = result.refused.join(" ") if result.refused.any?
    # the dropzone script posts with progress, then visits the list itself, where the messages wait
    return head(:ok) if request.format.json?

    redirect_to accounting_documents_path
  end

  def show
    authorize @document
    @links = @document.links.includes(:target)
    @downloadable = downloadable?
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
    return unless deliverable?

    send_file_data(inline: INLINE_TYPES.include?(@document.content_type))
  end

  def download
    authorize @document
    return unless deliverable?

    Accounting::AuditLog.record!(auditable: @document, action: "document_download", payload: { name: @document.name, sha256: @document.sha256 })
    send_file_data(inline: false)
  end

  # A person confirms, or corrects, one field proposed from the document.
  def confirm_field
    authorize @document
    result = Accounting::ConfirmDocumentField.call(document: @document, field: params[:field], value: params[:value], user: current_user)
    flash[result.success? ? :notice : :alert] = result.success? ? t("documents.field_confirmed") : result.message
    redirect_to accounting_document_path(@document)
  end

  # A prefilled DRAFT supplier invoice, linked to the document; the accountant adds the lines. Nothing is posted.
  def create_invoice
    authorize @document
    partner = Accounting::Partner.find_by(id: params[:partner_id])
    result = Accounting::CreateInvoiceFromDocument.call(document: @document, partner: partner, user: current_user, override_reason: params[:override_reason])
    if result.success?
      redirect_to edit_accounting_invoice_path(result[:invoice]), notice: t("documents.invoice_created")
    else
      redirect_to accounting_document_path(@document), alert: result.message
    end
  end

  # Places a document under legal hold, or releases it: nothing is deleted while it lasts.
  def legal_hold
    authorize @document
    result = Accounting::SetLegalHold.call(document: @document, hold: params[:hold] == "1", reason: params[:reason], user: current_user)
    flash[result.success? ? :notice : :alert] = result.success? ? t("documents.legal_hold_set") : result.message
    redirect_to accounting_document_path(@document)
  end

  # Cuts a PDF into one document per range of pages; the parent is never modified.
  def split
    authorize @document
    result = Accounting::SplitDocument.call(document: @document, ranges: params[:ranges], user: current_user)
    if result.success?
      flash[:notice] = t("documents.split_done", count: result[:children].size)
      flash[:alert] = result[:refused].join(" ") if result[:refused].any?
    else
      flash[:alert] = ([ result.message ] + result[:refused]).join(" ")
    end
    redirect_to accounting_document_path(@document)
  end

  # Reads the document again in the background; what a person confirmed is kept.
  def rerun
    authorize @document
    extraction = (@document.extracted_data["extraction"] || {}).merge("status" => "pending").except("error")
    @document.update_columns(extracted_data: @document.extracted_data.merge("extraction" => extraction), updated_at: Time.current)
    Accounting::ExtractDocumentJob.perform_later(@document.id, @document.entity_id)
    redirect_to accounting_document_path(@document), notice: t("documents.rerun")
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

  # A filter that is not a valid date or amount is ignored, never an error.
  def date_param(name)
    Date.iso8601(params[name].to_s)
  rescue Date::Error
    nil
  end

  def amount_param(name) = params[name].present? ? Accounting::DocumentFieldParser.parse_amount(params[name]) : nil

  # An external auditor is shown the file with their name on it, never the file as it is. What cannot be marked (a
  # spreadsheet, an XML) is theirs only if the owner allows read-only exports. Never sends an unmarked file by mistake.
  def deliverable?
    return true if downloadable?

    redirect_to accounting_document_path(@document), alert: t("documents.errors.cannot_be_shown")
    false
  end

  def downloadable?
    export_watermark.nil? || Accounting::WatermarkFile.markable?(@document.content_type) || Accounting::ReportPolicy.new(current_user, :report).export?
  end

  def send_file_data(inline:)
    response.set_header("X-Content-Type-Options", "nosniff")
    response.set_header("Content-Security-Policy", "default-src 'none'") unless inline
    bytes = file_bytes
    return unless bytes

    send_data bytes, type: @document.content_type, filename: @document.name, disposition: inline ? "inline" : "attachment"
  end

  def file_bytes
    bytes = @document.file.download
    return bytes unless (name = export_watermark) && Accounting::WatermarkFile.markable?(@document.content_type)

    Accounting::WatermarkFile.call(bytes, @document.content_type, name)
  rescue Accounting::WatermarkFile::Unavailable => e
    Rails.logger.error("[documents] watermark failed for document ##{@document.id}: #{e.message}")
    render plain: t("documents.errors.cannot_be_marked"), status: :service_unavailable
    nil
  end
end
