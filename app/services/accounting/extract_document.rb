# Reads a document and records what it found as PROPOSALS (F03): the fields an accountant would key in, each with the
# line and the page it came from and a flag telling whether a person confirmed it. It never creates an entry and never
# changes the document's kind. The proposals live in `extracted_data["extraction"]`, the text in `search_text`; a field a
# person already confirmed is never overwritten. Derived data is written even when the document is locked: the file and
# its details stay frozen, what was read from it does not need to.
#
# status: pending, done, unreadable (protected or damaged), low_confidence (OCR not sure: nothing kept),
# not_applicable (spreadsheet, CSV, an XML that is not an invoice), failed (error; raised so that the job can retry).
class Accounting::ExtractDocument
  OCR_TYPES = %w[image/png image/jpeg image/tiff].freeze

  def self.call(document:) = new(document).call

  def initialize(document)
    @document = document
  end

  def call
    ctx = LightService::Context.make(document: @document)
    outcome = read
    save(outcome)
    ctx
  rescue StandardError => e
    save(status: "failed", error: e.message)
    raise
  end

  private

  # => { status:, method:, confidence:, text:, fields: }
  def read
    return { status: "unreadable" } if @document.extracted_data["unreadable"]

    bytes = @document.file.download
    case @document.content_type
    when "application/pdf" then read_pdf(bytes)
    when *OCR_TYPES        then read_with_ocr(bytes, @document.content_type)
    when "application/xml" then read_ubl(bytes)
    else { status: "not_applicable" }
    end
  rescue Accounting::Extractors::Unreadable => e
    { status: "unreadable", error: e.message }
  end

  def read_pdf(bytes)
    result = Accounting::Extractors::PdfText.call(bytes)
    return read_with_ocr(bytes, "application/pdf") if result.confidence.nil? # a scan: no text layer

    from_text(result)
  end

  def read_with_ocr(bytes, content_type)
    result = Accounting::Extractors::Ocr.call(bytes, content_type)
    return { status: "low_confidence", method: result.method, confidence: result.confidence } if result.confidence.to_i < Accounting::Extractors::Ocr::MIN_CONFIDENCE

    from_text(result)
  end

  def read_ubl(bytes)
    result = Accounting::Extractors::Ubl.call(bytes)
    { status: "done", method: result.method, confidence: result.confidence, text: result.text, fields: result.fields }
  rescue Accounting::Extractors::Unreadable => e
    # An XML that is not an invoice is simply not for us; a damaged or unsafe one is unreadable.
    { status: e.message == "not an invoice" ? "not_applicable" : "unreadable", error: e.message }
  end

  def from_text(result)
    { status: "done", method: result.method, confidence: result.confidence, text: result.text, fields: Accounting::DocumentFieldParser.call(result.text) }
  end

  def save(outcome)
    previous = @document.extracted_data.dig("extraction", "fields") || {}
    fields = (outcome[:fields] || {}).to_h { |name, field| [ name.to_s, serialize(field) ] }
    previous.each { |name, field| fields[name] = field if field["confirmed"] } # a person's word stays
    extraction = { "status" => outcome[:status], "method" => outcome[:method], "confidence" => outcome[:confidence],
                   "error" => outcome[:error], "extracted_at" => Time.current.iso8601, "fields" => fields }.compact
    @document.update_columns(extracted_data: @document.extracted_data.merge("extraction" => extraction),
                             search_text: outcome[:text].presence, updated_at: Time.current)
  end

  def serialize(field) = field.transform_keys(&:to_s).merge("confidence" => field[:confidence].to_s, "confirmed" => false)
end
