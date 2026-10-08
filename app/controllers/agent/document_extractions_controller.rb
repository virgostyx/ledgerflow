# Reading documents with the model (A09), on a person's action only: one document from its page, or a batch of at most twenty the person chose after seeing the estimate. What was read waits as a proposal;
# the person confirms it field by field, or all at once when nothing is weak, through the door F03 already has (Accounting::ConfirmDocumentField). Nothing is confirmed, posted or sent by the assistant.
class Agent::DocumentExtractionsController < Agent::BaseController
  MAX_BATCH = 20
  TOKENS_PER_CHAR = 0.25 # a rough estimate; the instructions and the answer are added per document
  OVERHEAD_TOKENS = 900

  before_action { authorize Accounting::Document, :show? }
  before_action :set_extraction, only: %i[show confirm_field confirm_all reject]

  def index
    @extractions = Agent::DocumentExtraction.includes(:document, :requested_by).order(id: :desc).limit(100)
    @pending = @extractions.select(&:proposed?).size
  end

  # The estimate of a batch, before it starts.
  def new
    @documents = Accounting::Document.where(id: Array(params[:document_ids]).first(MAX_BATCH)).order(:id)
    @estimate = @documents.sum { |document| (document.search_text.to_s.length * TOKENS_PER_CHAR).ceil + OVERHEAD_TOKENS }
    @too_many = Array(params[:document_ids]).size > MAX_BATCH
    @candidates = Accounting::Document.inbox.where.not(search_text: [ nil, "" ]).order(created_at: :desc).limit(50) if @documents.empty?
  end

  def create
    ids = Array(params[:document_ids]).presence || Array(params[:document_id])
    return redirect_to(agent_document_extractions_path, alert: "Choose at most #{MAX_BATCH} documents.") if ids.size > MAX_BATCH || ids.empty?

    if ids.size == 1
      result = Agent::Documents::Extract.call(document: Accounting::Document.find(ids.first), user: current_user)
      redirect_to agent_document_extraction_path(result.extraction), result.ok? ? { notice: "The assistant read the document. Check what it found." } : { alert: result.error }
    else
      return redirect_to(new_agent_document_extraction_path(document_ids: ids), alert: "Confirm the estimate to start the reading.") unless params[:confirm_estimate] == "1"

      documents = Accounting::Document.where(id: ids)
      Agent::DocumentBatchJob.perform_later(current_user.id, ActsAsTenant.current_tenant.id, documents.pluck(:id), SecureRandom.hex(6))
      redirect_to agent_document_extractions_path, notice: "#{documents.size} documents are being read. The results appear below, to confirm."
    end
  end

  def show
    @document = @extraction.document
    @highlight = @extraction.fields[params[:field].to_s] if params[:field].present?
    @pages = @document.search_text.to_s.split("\f")
    @can_confirm = policy(@document).confirm_field? && !@document.locked?
  end

  def confirm_field
    return denied unless policy(@extraction.document).confirm_field?

    name = params[:name].to_s
    return back("This field is not part of the reading.") unless @extraction.fields.key?(name)

    value = params[:value].presence || @extraction.fields[name]["value"]
    problem = confirm_in_document(name, value)
    return back(problem) if problem

    @extraction.update_field!(name, "value" => value, "state" => "confirmed", "confirmed" => true, "confirmed_by" => current_user.id)
    @extraction.update!(status: "confirmed", confirmed_by: current_user, confirmed_at: Time.current) if @extraction.fields.values.all? { |field| field["state"] == "confirmed" || field["state"] == "not_found" }
    redirect_to agent_document_extraction_path(@extraction), notice: "Field confirmed.", status: :see_other
  end

  def confirm_all
    return denied unless policy(@extraction.document).confirm_field?
    return back("Some fields need your confirmation first: #{@extraction.weak_fields.join(', ')}.") unless @extraction.confirm_all?

    @extraction.fields.each do |name, field|
      next unless field["value"]

      problem = confirm_in_document(name, field["value"])
      return back("#{name}: #{problem}") if problem

      @extraction.update_field!(name, "state" => "confirmed", "confirmed" => true, "confirmed_by" => current_user.id)
    end
    @extraction.update!(status: "confirmed", confirmed_by: current_user, confirmed_at: Time.current)
    Accounting::AuditLog.record!(auditable: @extraction.document, action: "agent_document_confirm_all", user: current_user, payload: { extraction_id: @extraction.id })
    redirect_to agent_document_extraction_path(@extraction), notice: "All fields confirmed.", status: :see_other
  end

  def reject
    @extraction.update!(status: "rejected") if @extraction.proposed?
    Accounting::AuditLog.record!(auditable: @extraction.document, action: "agent_document_reject", user: current_user, payload: { extraction_id: @extraction.id })
    redirect_to agent_document_extractions_path, notice: "Reading rejected: nothing was kept in the document.", status: :see_other
  end

  private

  def set_extraction = @extraction = Agent::DocumentExtraction.includes(:document).find(params[:id])

  # The field goes into the document's data through the door of F03 (checked for its kind, audited with what was proposed and what was confirmed). A field F03 does not keep (the supplier's name) stays in the reading.
  def confirm_in_document(name, value)
    return nil unless Accounting::ConfirmDocumentField::FIELDS.include?(name)

    result = Accounting::ConfirmDocumentField.call(document: @extraction.document, field: name, value: value, user: current_user)
    result.success? ? nil : result.message
  end

  def back(message) = redirect_to(agent_document_extraction_path(@extraction), alert: message, status: :see_other)
  def denied = redirect_to(agent_document_extraction_path(@extraction), alert: "You may not confirm fields of documents.", status: :see_other)
end
