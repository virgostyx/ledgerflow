# The knowledge base screen (A06): the documents the agent may quote, their deposit, review and withdrawal. Anyone who may use the agent can read a document that was reviewed (a citation opens it);
# the rest needs `knowledge.manage`. A document of the platform or of an organization is read-only here.
class Agent::KnowledgeDocumentsController < Agent::BaseController
  before_action(except: :show) { authorize :agent, :manage_knowledge? }
  before_action :set_document, only: %i[show review retire new_version]
  before_action :require_editable, only: %i[review retire]

  REFUSALS = { empty: "The file or the text is empty.", too_large: "The file is too large (10 MB at most).", unsupported_type: "This kind of file is not supported (PDF, DOCX, HTML, Markdown or text).",
               unsafe_xml: "The file declares XML entities and was refused.", unreadable: "The text of the file could not be read.", infected: "The file was refused by the antivirus.",
               scan_unavailable: "The antivirus could not check the file: try again later.", no_text: "No text was found in the file.", invalid: "The description of the document is not complete." }.freeze

  def index
    @documents = Knowledge::Document.visible_to(current_entity).includes(:author).order(updated_at: :desc)
    @statistics = Knowledge::Statistics.new(current_entity)
  end

  def show
    @manager = policy(:agent).manage_knowledge?
    return head :not_found if @document.draft? && !@manager

    @chunks = @document.chunks.order(:position)
    @previous = @document.series_versions.where(version: ...@document.version).order(version: :desc).first
    # ponytail: lines present in one version and not in the other, not an aligned diff (diff-lcs is a test-only gem); a line moved shows as removed and added.
    @removed, @added = [ @previous.body, @document.body ].map { |body| body.lines.map(&:strip).reject(&:empty?) }.then { |old, new| [ old - new, new - old ] } if @previous
  end

  def new
    @document = Knowledge::Document.new(jurisdiction: current_entity.country.presence || "BE", language: "fr", valid_from: Date.current, source_type: "note")
  end

  def new_version
    @previous = @document
    @document = Knowledge::Document.new(@previous.slice(:title, :source, :licence, :source_type, :jurisdiction, :language).merge(valid_from: Date.current))
    render :new
  end

  def create
    previous = Knowledge::Document.visible_to(current_entity).find(params[:previous_id]) if params[:previous_id].present?
    return head :forbidden if previous && !previous.editable_by?(current_entity)

    upload = params.dig(:knowledge_document, :file)
    result = Knowledge::Ingest.call(attributes: document_params, user: current_user, entity: current_entity, new_version_of: previous,
                                    bytes: upload&.read, text: params.dig(:knowledge_document, :text))
    if result.success?
      notice = result.document.injection_suspected? ? "Added as a draft. Some text looks like an instruction to an AI: read it before you review it." : "Added as a draft. It is used once it is reviewed."
      redirect_to agent_knowledge_document_path(result.document), notice: notice
    else
      @document = Knowledge::Document.new(document_params)
      @previous = previous
      flash.now[:alert] = [ REFUSALS.fetch(result.reason), *result.errors ].join(" ")
      render :new, status: :unprocessable_entity
    end
  end

  def review
    @document.review!(current_user, four_eyes: current_entity.four_eyes?)
    @document.series_versions.where.not(id: @document.id).reviewed.find_each(&:retire!) if @document.version > 1 && params[:retire_previous] == "1"
    Accounting::AuditLog.record!(auditable: @document, action: "knowledge_document_review", user: current_user, payload: { title: @document.title, version: @document.version })
    redirect_to agent_knowledge_document_path(@document), notice: "Reviewed: the assistant can quote it from now on."
  rescue ArgumentError => error
    redirect_to agent_knowledge_document_path(@document), alert: error.message.capitalize + "."
  end

  def retire
    @document.retire!
    Accounting::AuditLog.record!(auditable: @document, action: "knowledge_document_retire", user: current_user, payload: { title: @document.title, version: @document.version })
    redirect_to agent_knowledge_document_path(@document), notice: "Withdrawn. Earlier answers that quoted it still open it, marked as withdrawn."
  end

  private

  def current_entity = ActsAsTenant.current_tenant

  def set_document = @document = Knowledge::Document.visible_to(current_entity).find(params[:id])

  def require_editable = (head :forbidden unless @document.editable_by?(current_entity))

  def document_params = params.require(:knowledge_document).permit(:title, :source, :licence, :source_type, :jurisdiction, :language, :valid_from, :valid_to)
end
