# B02b: takes what a person of the portal sent out of quarantine, on the firm's side. The type is read from the bytes, a PDF is rewritten (through PostScript: no script, no action,
# no embedded file survives), a photo is turned upright, reduced and made a JPEG (a HEIC too), photos of one batch become one PDF, then the file goes through the ordinary upload of
# the inbox (F03: antivirus, integrity, duplicates, audit) as a document of origin `portal`. Nothing is executed, nothing is read by a model, and the client decides nothing about how it is booked.
# `uploads` is one upload or, for a batch of photos, all its pages in order. A refusal is written on the uploads with its reason; an antivirus that cannot answer leaves them waiting.
class PortalAdmin::ReceiveUpload
  MAX_PIXELS = 100_000_000
  MAX_PAGES = 100
  EDGE = 2000
  HEIC_BRANDS = %w[heic heix hevc hevx heim heis mif1 msf1].freeze
  IMAGE_TYPES = %i[jpeg png tiff heic].freeze
  CONVERT_LIMITS = %w[-limit memory 512MiB -limit map 512MiB -limit area 256MP -limit time 60].freeze
  Refusal = Class.new(StandardError)
  Waiting = Class.new(StandardError)

  def self.call(uploads) = new(Array(uploads)).call

  def initialize(uploads)
    @uploads = uploads
    @first = uploads.first
  end

  def call
    ActsAsTenant.with_tenant(Entity.find(@first.entity_id)) { process }
    @uploads
  end

  private

  def process
    sent = @uploads.map(&:bytes)
    raise Refusal, "duplicate" if @uploads.one? && sent_before?
    check_virus(sent)
    filename, bytes = @uploads.one? && !@first.batch_token ? [ @first.filename, clean(sent.first) ] : pdf_of_photos(sent)
    outcome = Accounting::UploadDocument.call(io: StringIO.new(bytes), filename: filename, user: nil, origin: :portal, details: details)
    return refuse(outcome[:reason].to_s) unless outcome.success?

    accept(outcome[:document])
  rescue Refusal => e
    refuse(e.message)
  rescue Waiting
    Rails.logger.warn("[portal] upload #{@first.token}: antivirus not available, waiting")
  rescue Accounting::ExternalCommand::Failed => e
    Rails.logger.error("[portal] upload #{@first.token}: #{e.message}")
    refuse("corrupted")
  end

  # The same file already taken in from this company: one document, a clear message.
  def sent_before?
    Portal::Upload.where(entity_id: @first.entity_id, sha256: @first.sha256, status: %w[accepted to_complete]).where.not(id: @first.id).exists?
  end

  def check_virus(sent)
    sent.each do |bytes|
      case Accounting::VirusScan.call(bytes)
      when :infected    then raise Refusal, "infected"
      when :unavailable then raise Waiting # nothing is let in unchecked: tried again at the next round
      end
    end
  end

  def details
    task = Portal::Question.find_by(id: @first.question_id)&.task_id
    { **({ task_id: task, question_id: @first.question_id } if task).to_h, portal_hint: { kind: @first.hint_kind, note: @first.hint_note, sent_sha256: @uploads.one? ? @first.sha256 : @uploads.map(&:sha256) },
      source: { portal_user: @first.portal_user.full_name, portal_user_id: @first.portal_user_id, upload: @first.token } }
  end

  def accept(document)
    status = document.extracted_data["unreadable"] ? "to_complete" : "accepted"
    ApplicationRecord.transaction do
      @uploads.each do |upload|
        upload.update!(status: status, document_id: document.id)
        upload.purge_chunks!
      end
      Accounting::AuditLog.record!(auditable: @first, action: "portal_upload_#{status}", payload: audit_payload.merge(document_id: document.id))
    end
    link_to_requested_line(document)
    PortalAdmin::NotifyUpload.call(@first) if status == "to_complete"
  end

  # A document sent for a line the firm asked about is linked to that bank line (a link, nothing is booked). A line withdrawn meanwhile keeps the document in the inbox.
  def link_to_requested_line(document)
    line = Portal::DocumentRequestLine.open_ones.find_by(id: @first.request_line_id) if @first.request_line_id
    transaction = Accounting::BankTransaction.find_by(id: line.bank_transaction_id) if line
    Accounting::LinkDocument.call(document: document, target: transaction, user: nil) if transaction
  end

  def refuse(reason)
    ApplicationRecord.transaction do
      @uploads.each { |upload| upload.update!(status: "refused", refusal_reason: reason) && upload.purge_chunks! }
      Accounting::AuditLog.record!(auditable: @first, action: "portal_upload_refused", payload: audit_payload.merge(reason: reason))
    end
    PortalAdmin::NotifyUpload.call(@first)
  end

  def audit_payload = { upload: @first.token, filename: @first.filename, portal_user_id: @first.portal_user_id, sent_sha256: @uploads.map(&:sha256) }

  # --- what is sent, made safe -------------------------------------------------------------------------------

  def sniff(bytes)
    if bytes.byteslice(0, 1024).include?("%PDF-") then :pdf
    elsif bytes.start_with?("\x89PNG\r\n\x1a\n".b) then :png
    elsif bytes.start_with?("\xFF\xD8\xFF".b) then :jpeg
    elsif bytes.start_with?("II*\x00".b, "MM\x00*".b) then :tiff
    elsif bytes.byteslice(4, 4) == "ftyp" && HEIC_BRANDS.include?(bytes.byteslice(8, 4)) then :heic
    end
  end

  def clean(bytes)
    case (type = sniff(bytes))
    when :pdf then sanitize_pdf(bytes)
    when *IMAGE_TYPES then normalize_image(bytes, type)
    else bytes # a spreadsheet, a CSV, anything else: the upload of the inbox decides
    end
  end

  # PDF -> PostScript -> PDF: what the second pass writes is only pages, fonts and images. A PDF that asks for a password cannot be rewritten: it is kept and to be completed.
  def sanitize_pdf(bytes)
    return bytes if password_protected?(bytes)

    ps = Accounting::ExternalCommand.run(*gs("ps2write"), input: bytes, timeout: 90)
    pdf = Accounting::ExternalCommand.run(*gs("pdfwrite"), input: ps, timeout: 90).b
    pages = PDF::Reader.new(StringIO.new(pdf)).page_count
    raise Refusal, "corrupted" if pages.zero?
    raise Refusal, "too_many_pages" if pages > MAX_PAGES

    pdf
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
    raise Refusal, "corrupted"
  end

  def gs(device) = [ "gs", "-q", "-dSAFER", "-dBATCH", "-dNOPAUSE", "-sDEVICE=#{device}", "-sOutputFile=-", "-" ]

  def password_protected?(bytes)
    PDF::Reader.new(StringIO.new(bytes)).page_count
    false
  rescue PDF::Reader::EncryptedPDFError
    true
  rescue StandardError
    false
  end

  # Whatever the phone sent becomes an upright JPEG of 2000 pixels at most. The format is the one we read from the bytes, never a guess of ImageMagick; the size is read from the header
  # before anything is decoded.
  def normalize_image(bytes, type)
    source = "#{type}:-[0]"
    width, height = Accounting::ExternalCommand.run("identify", "-ping", "-format", "%w %h", source, input: bytes, timeout: 30).split.map(&:to_i)
    raise Refusal, "corrupted" unless width&.positive? && height&.positive?
    raise Refusal, "image_too_large" if width * height > MAX_PIXELS

    Accounting::ExternalCommand.run("convert", *CONVERT_LIMITS, source, "-auto-orient", "-strip", "-background", "white", "-alpha", "remove", "-alpha", "off",
                                    "-resize", "#{EDGE}x#{EDGE}>", "-interlace", "None", "-quality", "80", "jpeg:-", input: bytes, timeout: 60).b
  end

  def pdf_of_photos(sent)
    types = sent.map { |bytes| sniff(bytes) }
    raise Refusal, "unsupported_type" unless types.all? { |t| IMAGE_TYPES.include?(t) }

    pages = sent.zip(types).map { |bytes, type| normalize_image(bytes, type) }
    pdf = Prawn::Document.new(page_size: "A4", margin: 20, skip_page_creation: true)
    pages.each do |jpeg|
      pdf.start_new_page
      pdf.image(StringIO.new(jpeg), fit: [ pdf.bounds.width, pdf.bounds.height ], position: :center, vposition: :center)
    end
    [ "#{File.basename(@first.filename, '.*')}.pdf", pdf.render.b ]
  end
end
