require "csv"

# F13b: the full backup of an entity for portability: every dataset (all periods, CSV and JSON), the documents of F03 with an index, the
# audit trail with its hash chain (one JSON line per record) and a `manifest.json` that gives the SHA-256 and size of every other file. The ZIP is
# written to disk file by file, so that neither the documents nor the ledger are held in memory. `verify` re-reads a backup against its manifest.
class Exports::Backup
  Verification = Struct.new(:checked, :mismatches, :missing, :unlisted, keyword_init: true) do
    def valid? = mismatches.empty? && missing.empty? && unlisted.empty?
  end

  SCHEMA_VERSION = 1

  def self.call(data_export:) = new(data_export).call

  # => Verification, from ZIP data (String) or a Pathname; each file is read once, in turn
  def self.verify(zip)
    manifest, hashes = nil, {}
    Zip::File.open_buffer(StringIO.new(zip.is_a?(Pathname) ? zip.binread : zip)) do |file|
      file.each do |entry|
        content = entry.get_input_stream.read
        manifest = JSON.parse(content) if entry.name == "manifest.json"
        hashes[entry.name] = Digest::SHA256.hexdigest(content)
      end
    end
    listed = manifest.fetch("files")
    paths = listed.map { |f| f["path"] }
    Verification.new(checked: listed.size, missing: paths - hashes.keys, unlisted: hashes.keys - paths - [ "manifest.json" ],
                     mismatches: listed.select { |f| hashes.key?(f["path"]) && hashes[f["path"]] != f["sha256"] }.map { |f| f["path"] })
  end

  def initialize(data_export)
    @export = data_export
    @files = []
  end

  def call
    ActsAsTenant.with_tenant(@export.entity) do
      Tempfile.create([ "backup", ".zip" ], binmode: true) do |tmp|
        Zip::OutputStream.open(tmp.path) do |zip|
          @zip = zip
          Exports::Standard::DATASETS.each_key do |name|
            standard = Exports::Standard.new(name)
            add("data/#{name}.csv", standard.csv)
            add("data/#{name}.json", standard.json)
          end
          add("audit/audit_log.jsonl", audit_lines)
          add_documents
          add("manifest.json", [ JSON.pretty_generate(manifest) ], listed: false)
        end
        @export.file.attach(io: File.open(tmp.path, "rb"), filename: "backup-#{@export.entity_id}-#{Date.current}.zip", content_type: "application/zip")
        @export.update!(status: "ready", file_count: @files.size, bytes: File.size(tmp.path), expires_at: DataExport::KEEP_FOR.from_now, error: nil)
      end
    end
  end

  private

  # `chunks` answers #each with strings: written as they come, the hash and size kept for the manifest.
  def add(path, chunks, listed: true)
    @zip.put_next_entry(Zip::Entry.new(nil, path, time: Zip::DOSTime.new(2000, 1, 1, 0, 0, 0)))
    digest, bytes = Digest::SHA256.new, 0
    chunks.each { |chunk| @zip.write(chunk); digest << chunk; bytes += chunk.bytesize }
    @files << { path: path, sha256: digest.hexdigest, bytes: bytes } if listed
  end

  def audit_lines
    Enumerator.new do |out|
      Accounting::AuditLog.order(:id).in_batches(of: 1_000) do |batch|
        out << batch.map { |log|
          JSON.generate(id: log.id, created_at: log.created_at.utc.iso8601(6), user_email: log.user_email, action: log.action, auditable_type: log.auditable_type,
                        auditable_id: log.auditable_id, reason: log.reason, payload: log.payload, previous_hash: log.previous_hash, content_hash: log.content_hash) + "\n"
        }.join
      end
    end
  end

  def add_documents
    index = [ CSV.generate_line(%w[id name kind status sha256 bytes path]) ]
    Accounting::Document.includes(file_attachment: :blob).order(:id).find_each do |document|
      next unless document.file.attached?

      path = "documents/#{document.id}-#{document.name.gsub(/[^\w.\-]/, '_')}"
      add(path, Enumerator.new { |out| document.file.download { |chunk| out << chunk } })
      index << CSV.generate_line([ document.id, document.name, document.kind, document.status, document.sha256, document.byte_size, path ])
    end
    add("documents/index.csv", index)
  end

  def manifest
    { schema_version: SCHEMA_VERSION, entity: { id: @export.entity_id, name: @export.entity.name }, generated_at: Time.current.utc.iso8601,
      generated_by: @export.user&.email, files: @files.sort_by { |f| f[:path] } }
  end
end
