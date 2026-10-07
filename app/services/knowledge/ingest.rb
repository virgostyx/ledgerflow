# Puts a document in the knowledge base as a draft (A06): the file is checked like any document of F03 (size, type read from the bytes, virus scan), its text read, cut into passages and indexed. Nothing is
# used by the agent until a person reviews it. A text that looks like an instruction to an AI is not refused (it may be a legitimate note) but marked, and told to the person.
# `attributes` are the metadata of the document (title, source, licence, ...). `new_version_of` makes a new version of an existing series.
# => Result with `document` or `reason` (:empty, :too_large, :unsupported_type, :unsafe_xml, :unreadable, :infected, :scan_unavailable, :no_text, :invalid).
class Knowledge::Ingest
  MAX_BYTES = 10.megabytes
  Result = Data.define(:document, :reason, :errors) do
    def success? = reason.nil?
  end

  def self.call(attributes:, user:, entity:, bytes: nil, text: nil, new_version_of: nil) = new(attributes, user, entity, bytes, text, new_version_of).call

  def initialize(attributes, user, entity, bytes, text, new_version_of)
    @attributes = attributes.to_h.symbolize_keys.slice(:title, :source, :licence, :source_type, :jurisdiction, :language, :valid_from, :valid_to)
    @user = user
    @entity = entity
    @bytes = bytes
    @text = text
    @previous = new_version_of
  end

  def call
    body = read or return refuse(@reason)
    passages = Knowledge::Chunker.call(body)
    return refuse(:no_text) if passages.empty?

    document = build(body)
    return Result.new(nil, :invalid, document.errors.full_messages) unless document.valid?

    ApplicationRecord.transaction do
      document.save!
      passages.each_with_index { |passage, index| document.chunks.create!(position: index + 1, section: passage.section, content: passage.content, quality: passage.quality, config: Knowledge::Chunk::CONFIGS.fetch(document.language)) }
      index(document)
      Accounting::AuditLog.record!(auditable: document, action: "knowledge_document_add", user: @user, payload: { title: document.title, version: document.version, sha256: document.content_sha256 })
    end
    Result.new(document, nil, [])
  end

  private

  # The text of the document, or nil with @reason set.
  def read
    return fail_with(:empty) if @bytes.nil? && @text.to_s.strip.empty?
    return @text.to_s.strip if @bytes.nil?

    bytes = @bytes.to_s.b
    return fail_with(:empty) if bytes.empty?
    return fail_with(:too_large) if bytes.bytesize > MAX_BYTES

    scan = Accounting::VirusScan.call(bytes)
    return fail_with(:infected) if scan == :infected
    return fail_with(:scan_unavailable) if scan == :unavailable

    Knowledge::Extract.call(bytes)
  rescue Knowledge::Extract::Refused => error
    fail_with(error.reason)
  end

  def fail_with(reason)
    @reason = reason
    nil
  end

  def refuse(reason) = Result.new(nil, reason, [])

  def build(body)
    previous = @previous
    Knowledge::Document.new(@attributes.reverse_merge(language: previous&.language, jurisdiction: previous&.jurisdiction, source_type: previous&.source_type).compact.merge(
      scope: "company", entity: @entity, author: @user, body: body, content_sha256: Digest::SHA256.hexdigest(body),
      series: previous&.series || SecureRandom.uuid, version: previous ? previous.series_versions.maximum(:version) + 1 : 1,
      injection_suspected: Agent::InjectionDetector.scan(body).any?
    ))
  end

  # The full text index: the section title weighs more than the text; the configuration is the language of the document; accents do not matter.
  def index(document)
    Knowledge::Chunk.where(document_id: document.id).update_all(
      "search_vector = setweight(to_tsvector(config::regconfig, f_unaccent(coalesce(section, ''))), 'A') || to_tsvector(config::regconfig, f_unaccent(content))"
    )
  end
end
