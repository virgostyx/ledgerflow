# Reads a document the local extraction does not handle (A09), at the request of a person: the isolated reading by the model (Agent::Documents::Reading), then the supplier and the duplicate, then a proposal kept
# for the person to confirm. Local first: an invoice in UBL is read by the deterministic mapper of F03/F06 and the model is not called. The text that leaves is the masked text (no file, no image), the call has
# one tool and no other, and a value is kept only if it is in the document. Nothing here writes to the books or confirms a field.
# => Result(extraction:, error:)
class Agent::Documents::Extract
  Result = Struct.new(:extraction, :error) do
    def ok? = error.nil?
  end

  PER_HOUR = 40 # documents one person may have read by the model in an hour (a batch counts for each of its documents)
  ENTRY_TYPES = %w[invoice credit_note].freeze
  Supplier = Struct.new(:id, :matched_by)

  def self.call(document:, user:, batch_key: nil, gateway: Agent::ModelGateway.default) = new(document, user, batch_key, gateway).call

  def initialize(document, user, batch_key, gateway)
    @document = document
    @user = user
    @batch_key = batch_key
    @gateway = gateway
  end

  def call
    context = Agent::Context.build(user: @user, entity: ActsAsTenant.current_tenant, locale: I18n.locale)
    return fail_with("The assistant is not available to you here.") if Agent::Access.check(context)
    return fail_with("You reached the limit of #{PER_HOUR} documents read per hour. Try again a little later.") if Agent::DocumentExtraction.where(requested_by_id: @user.id, created_at: 1.hour.ago..).count >= PER_HOUR

    local = @document.extracted_data["extraction"] || {}
    return fail_with("This document is protected or damaged: nothing could be read, and the model was not asked.") if local["status"] == "unreadable"
    return save("ubl", ubl(local)) if local["method"].to_s.include?("ubl") && local["status"] == "done"

    text = @document.search_text.to_s
    return fail_with("No text was read from this document yet (a scan the local reading could not use?): read it again first. The model was not asked.") if text.strip.empty?

    reading = Agent::Documents::Reading.call(text: text, user: @user, gateway: @gateway)
    note_suspicion(context, text) if reading.suspicious
    save("agent_text", reading)
  rescue Agent::Documents::Reading::Error => e
    fail_with(e.message)
  rescue Agent::LiveProviderRefused
    fail_with("The live provider is off in this environment.")
  end

  private

  # An invoice that is already structured: its fields as the mapper read them, checked like any other, and no model.
  def ubl(local)
    fields = local.fetch("fields", {}).except("supplier_partner_id").slice(*Agent::Documents::Submission::FIELD_NAMES).transform_values do |field|
      { "value" => field["value"], "confidence" => "high", "page" => field["page"], "snippet" => field["snippet"], "state" => "ok" }
    end
    verdict = Agent::Documents::Validation.call(fields.transform_values { |field| field["value"] })
    fields.each { |name, field| field["validation"] = verdict.fields[name] }
    Agent::Documents::Reading::Result.new(type: "invoice", fields: fields, lines: [], breakdown: [], checks: verdict.document, warnings: [], sent: nil, usage: {}, model: nil, suspicious: false, coverage: "full")
  end

  def save(engine, reading)
    fields = reading.fields
    warnings = reading.warnings.dup
    supplier = match_supplier(fields, warnings)
    fields["supplier_partner_id"] = { "value" => supplier.id.to_s, "state" => "ok", "confidence" => "high", "matched_by" => supplier.matched_by } if supplier
    warnings << "A probable duplicate: an invoice with this supplier, number and total already exists." if duplicate?(supplier, fields)
    warnings << "A #{reading.type.tr('_', ' ')} does not give an entry: no entry will be proposed from it." unless ENTRY_TYPES.include?(reading.type)
    usage = reading.usage || {}
    extraction = Agent::DocumentExtraction.create!(document: @document, requested_by: @user, engine: engine, document_type: reading.type, coverage: reading.coverage, suspicious: reading.suspicious, model: reading.model, batch_key: @batch_key,
                                                   input_tokens: usage[:input_tokens].to_i, output_tokens: usage[:output_tokens].to_i,
                                                   payload: { "fields" => fields, "lines" => reading.lines, "vat_breakdown" => reading.breakdown, "validation" => reading.checks, "warnings" => warnings, "sent" => reading.sent }.to_json)
    Accounting::AuditLog.record!(auditable: @document, action: "agent_document_extract", user: @user, payload: { extraction_id: extraction.id, engine: engine, model: reading.model, tokens: [ usage[:input_tokens].to_i, usage[:output_tokens].to_i ] })
    Result.new(extraction, nil)
  end

  # By VAT number, then by IBAN, as F06 does: exactly one partner wins, several are a problem to leave to the person.
  def match_supplier(fields, warnings)
    candidates = []
    candidates << [ "vat_number", Accounting::Partner.where("REPLACE(REPLACE(UPPER(vat_number), ' ', ''), '.', '') = ?", fields.dig("supplier_vat", "value")) ] if fields.dig("supplier_vat", "value")
    candidates << [ "iban", Accounting::Partner.where("upper(replace(iban, ' ', '')) = ?", fields.dig("iban", "value")) ] if fields.dig("iban", "value")
    candidates.each do |by, scope|
      found = scope.limit(2).to_a
      return Supplier.new(found.first.id, by) if found.one?

      warnings << "Several partners share the #{by.tr('_', ' ')} of this supplier: pick the right one." if found.size > 1
    end
    nil
  end

  def duplicate?(supplier, fields)
    number, total = fields.dig("invoice_number", "value"), fields.dig("total", "value")
    supplier && number && total && Accounting::Invoice.where(partner_id: supplier.id, external_ref: number, total_incl_vat: BigDecimal(total)).exists?
  end

  def note_suspicion(context, text)
    event = Agent::SecurityEvent.create!(entity: context.entity, user: @user, kind: "suspicious_content", tool: Agent::Documents::Submission::NAME, excerpt: Agent::Security.mask_excerpt(Agent::InjectionDetector.scan(text).join(", ")))
    Accounting::AuditLog.record!(auditable: event, action: "agent_security_event", user: @user, payload: { kind: "suspicious_content", tool: Agent::Documents::Submission::NAME })
  end

  def fail_with(message)
    extraction = Agent::DocumentExtraction.create!(document: @document, requested_by: @user, engine: "agent_text", status: "failed", error: message.first(200), batch_key: @batch_key)
    Result.new(extraction, message)
  end
end
