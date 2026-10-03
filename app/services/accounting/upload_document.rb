# Takes a file into the document store (F03). Nothing is trusted from the upload: the type is read from the bytes
# (never the extension), every type gets an integrity check, an XML that declares entities is refused, a file already
# in the entity (same SHA-256) is refused with a pointer to the first one, and nothing is ever executed or resolved.
# Failure reasons: :empty, :too_large, :unsupported_type, :corrupted, :unsafe_xml, :duplicate.
class Accounting::UploadDocument
  MAX_BYTES = 25.megabytes
  XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze
  CODA_HEADER = /\A00000\d{6}\d{3}05[ D]/n
  TYPES = { pdf: "application/pdf", png: "image/png", jpeg: "image/jpeg", tiff: "image/tiff", xml: "application/xml", csv: "text/csv", xlsx: XLSX, coda: "text/x-coda" }.freeze

  # `io` anything with #read; `filename` as the person knows it.
  def self.call(io:, filename:, user:, origin: :manual_upload, kind: nil, parent: nil, details: {}) = new(io, filename, user, origin, kind, parent, details).call

  def initialize(io, filename, user, origin, kind, parent = nil, details = {})
    @bytes    = io.read.to_s.b
    @filename = filename.to_s
    @user     = user
    @origin   = origin
    @kind     = kind
    @parent   = parent
    @details  = details
  end

  def call
    return refuse(:empty) if @bytes.empty?
    return refuse(:too_large) if @bytes.bytesize > MAX_BYTES

    type = detect_type
    return refuse(:unsupported_type) unless type
    return refuse(:unsafe_xml) if type == :xml && unsafe_xml?

    case Accounting::VirusScan.call(@bytes)
    when :infected    then return refuse(:infected)
    when :unavailable then return refuse(:scan_unavailable)
    end

    extracted = @details.deep_stringify_keys
    problem = check_integrity(type, extracted)
    return refuse(problem) if problem

    sha256 = Digest::SHA256.hexdigest(@bytes)
    existing = Accounting::Document.find_by(sha256: sha256)
    return refuse(:duplicate, existing: existing, name: existing&.name) if existing

    store(type, sha256, extracted)
  end

  private

  def store(type, sha256, extracted)
    status = extraction_status(type, extracted)
    extracted["extraction"] = { "status" => status }
    document = Accounting::Document.new(name: @filename, content_type: TYPES.fetch(type), byte_size: @bytes.bytesize, sha256: sha256,
                                        origin: @origin, kind: @kind || :other, uploaded_by: @user, parent: @parent, extracted_data: extracted)
    document.file.attach(io: StringIO.new(@bytes), filename: storage_filename, content_type: TYPES.fetch(type))
    ApplicationRecord.transaction do
      document.save!
      Accounting::AuditLog.record!(auditable: document, action: "document_upload", user: @user,
                                   payload: { name: document.name, sha256: sha256, byte_size: document.byte_size, content_type: document.content_type, origin: @origin.to_s })
    end
    Accounting::ExtractDocumentJob.perform_later(document.id, document.entity_id) if status == "pending"
    LightService::Context.make(document: document)
  end

  # What is read later by the job ("pending"), what cannot be read, and what has nothing to read.
  def extraction_status(type, extracted)
    if extracted["unreadable"] then "unreadable"
    elsif %i[pdf png jpeg tiff xml].include?(type) then "pending"
    else "not_applicable"
    end
  end

  def refuse(reason, **extra)
    LightService::Context.make(document: nil, reason: reason, **extra).tap { |ctx| ctx.fail!(I18n.t("documents.errors.#{reason}", **extra)) }
  end

  # Displayed as given; stored under a name safe for any file system.
  def storage_filename = I18n.transliterate(@filename).gsub(/[^\w.\- ()]/, "_")

  # --- type, from the bytes ----------------------------------------------------------------------------------

  def detect_type
    head = @bytes.byteslice(0, 1024)
    if head.include?("%PDF-") then :pdf
    elsif @bytes.start_with?("\x89PNG\r\n\x1a\n".b) then :png
    elsif @bytes.start_with?("\xFF\xD8\xFF".b) then :jpeg
    elsif @bytes.start_with?("II*\x00".b, "MM\x00*".b) then :tiff
    elsif @bytes.start_with?("PK\x03\x04".b) then zip_type
    elsif text? then text_type
    end
  end

  def zip_type
    names = Zip::File.open_buffer(StringIO.new(@bytes)).entries.map(&:name)
    :xlsx if names.include?("xl/workbook.xml")
  rescue StandardError
    nil
  end

  def text? = @bytes.byteslice(0, 8192).then { |chunk| !chunk.include?("\x00") && chunk.count("\x01-\x08\x0B\x0C\x0E-\x1F").zero? }

  def text_type
    stripped = @bytes.sub(/\A\xEF\xBB\xBF/n, "").lstrip
    if stripped.start_with?("<") then :xml
    elsif coda? then :coda
    elsif File.extname(@filename).casecmp?(".csv") then :csv
    end
  end

  # A CODA bank statement (F02): a first record of 128 characters that is the header (record 0, application code 05). The
  # parser (Banking::Coda::Parser) does the real reading; here it is only told apart from other text.
  def coda?
    first = @bytes.byteslice(0, 300).to_s.split(/\r\n|\n|\r/, 2).first.to_s
    first.bytesize == 128 && first.match?(CODA_HEADER)
  end

  def unsafe_xml? = @bytes.match?(/<!DOCTYPE|<!ENTITY/i)

  # --- integrity, per type -----------------------------------------------------------------------------------

  def check_integrity(type, extracted)
    case type
    when :pdf  then check_pdf(extracted)
    when :png  then :corrupted unless @bytes.byteslice(-12, 12).to_s.include?("IEND")
    when :jpeg then :corrupted unless @bytes.end_with?("\xFF\xD9".b)
    when :xml  then check_xml(extracted)
    end
  end

  def check_pdf(extracted)
    extracted["pages"] = PDF::Reader.new(StringIO.new(@bytes)).page_count
    nil
  rescue PDF::Reader::EncryptedPDFError, PDF::Reader::UnsupportedFeatureError
    extracted["unreadable"] = "password_protected" # kept as evidence, nothing to read from it
    nil
  rescue StandardError
    :corrupted
  end

  def check_xml(extracted)
    doc = Nokogiri::XML(@bytes) { |config| config.strict.nonet }
    extracted["xml_root"] = doc.root&.name
    nil
  rescue Nokogiri::XML::SyntaxError
    :corrupted
  end
end
