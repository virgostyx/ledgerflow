# F13a step 1-2: the file is read (to be sure it can be), kept with its batch, and a mapping is proposed: the one of a saved template,
# else the columns whose title is the name of a field. Nothing else is written. => the batch
class Imports::Start
  DEFAULT_OPTIONS = { "date_format" => "iso", "decimal" => "." }.freeze

  def self.call(user:, kind:, filename:, data:, options: {}, template: nil)
    table = Imports::Reader.read(data, filename: filename)
    klass = Imports::Kind.for(kind) or raise Imports::Reader::Unreadable, "Unknown kind of import"

    batch = Accounting::ImportBatch.create!(
      user: user, kind: kind, parser: "guided_#{File.extname(filename).delete('.').downcase}", source_name: filename, filename: filename,
      file_sha256: Digest::SHA256.hexdigest(data), result: "uploaded", lines_read: table.rows.size,
      mapping: template&.mapping || klass.propose_mapping(table.headers), options: DEFAULT_OPTIONS.merge(template&.options || {}).merge(options.to_h.stringify_keys)
    )
    batch.queued_file.attach(io: StringIO.new(data), filename: filename)
    batch
  end
end
