# The one way files come into the document store (F03): the manual upload and the dedicated mailbox. Each file is an
# upload (Accounting::UploadDocument); a ZIP archive is unpacked, each file inside being an upload, and is not kept.
# Unpacking is bounded (Rails.configuration.x.document_archive_limits: files, total bytes, compression ratio) and
# nothing from the archive is ever written to disk or trusted: only the name of a file is kept (never a path), no archive
# inside an archive is opened, a file that decompresses suspiciously is not read. A spreadsheet is not an archive.
# => Result(created: [documents], refused: ["name: reason"])
class Accounting::UploadFiles
  Result = Struct.new(:created, :refused, keyword_init: true)

  LITTER = %r{\A(__MACOSX/|\.DS_Store\z|Thumbs\.db\z|\._)}i

  # files: [[io, filename], ...]
  def self.call(files:, user:, origin: :manual_upload, kind: nil, details: {}) = new(files, user, origin, kind, details).call

  def initialize(files, user, origin, kind, details = {})
    @files = files
    @user = user
    @origin = origin
    @kind = kind
    @details = details
    @result = Result.new(created: [], refused: [])
  end

  def call
    @files.each do |io, filename|
      bytes = io.read.to_s.b
      if (archive = open_archive(bytes, filename))
        unpack(archive, filename)
      elsif filename.to_s.downcase.end_with?(".zip") && bytes.start_with?("PK\x03\x04".b)
        @result.refused << "#{filename}: #{I18n.t('documents.errors.damaged_archive')}"
      else
        upload(bytes, filename)
      end
    end
    @result
  end

  private

  def limits = Rails.configuration.x.document_archive_limits

  # The archive, or nil when it is not a ZIP, is a spreadsheet (a ZIP that holds xl/workbook.xml) or cannot be opened.
  def open_archive(bytes, _filename)
    return unless bytes.start_with?("PK\x03\x04".b)

    zip = Zip::File.open_buffer(StringIO.new(bytes))
    zip.entries.any? { |entry| entry.name == "xl/workbook.xml" } ? nil : zip
  rescue StandardError
    nil
  end

  def unpack(zip, archive_name)
    entries = zip.entries.reject { |entry| entry.directory? || entry.name.match?(LITTER) || File.basename(entry.name).match?(LITTER) }
    return @result.refused << "#{archive_name}: #{I18n.t('documents.errors.empty_archive')}" if entries.empty?

    declared = entries.sum(&:size)
    if declared > limits[:bytes]
      return @result.refused << "#{archive_name}: #{I18n.t('documents.errors.archive_too_large', limit: ActiveSupport::NumberHelper.number_to_human_size(limits[:bytes]))}"
    end

    entries.each_with_index do |entry, index|
      name = "#{archive_name} / #{File.basename(entry.name)}"
      if index >= limits[:files]
        @result.refused << "#{name}: #{I18n.t('documents.errors.archive_limit', count: limits[:files])}"
      else
        unpack_entry(entry, name)
      end
    end
  end

  def unpack_entry(entry, name)
    return @result.refused << "#{name}: #{I18n.t('documents.errors.archive_password')}" if entry.gp_flags.to_i.anybits?(1)
    return @result.refused << "#{name}: #{I18n.t('documents.errors.archive_ratio')}" if entry.compressed_size.positive? && entry.size / entry.compressed_size > limits[:ratio]

    bytes = entry.get_input_stream { |stream| stream.read(Accounting::UploadDocument::MAX_BYTES + 1) }.to_s.b
    return @result.refused << "#{name}: #{I18n.t('documents.errors.nested_archive')}" if bytes.start_with?("PK\x03\x04".b) && open_archive(bytes, name)

    upload(bytes, File.basename(entry.name), shown_as: name)
  rescue StandardError => e
    @result.refused << "#{name}: #{e.message.presence || I18n.t('documents.errors.corrupted')}"
  end

  def upload(bytes, filename, shown_as: filename)
    outcome = Accounting::UploadDocument.call(io: StringIO.new(bytes), filename: File.basename(filename.to_s.tr("\\", "/")), user: @user, origin: @origin, kind: @kind, details: @details)
    outcome.success? ? @result.created << outcome[:document] : @result.refused << "#{shown_as}: #{outcome.message}"
  end
end
