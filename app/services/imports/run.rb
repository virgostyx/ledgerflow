# F13a steps 4-5: the simulation (everything is worked out and written, then rolled back: nothing stays) and the import itself, in
# chunks that each commit so that a long import shows its progress. Only what is valid is written; the refused are listed with their cause.
# A batch that wrote nothing stays `uploaded`: its mapping and its links can be corrected and it can be run again. => the batch
class Imports::Run
  CHUNK = 500
  BACKGROUND_ABOVE = 5_000 # rows: past it, the import runs in a job

  def self.call(batch:, user:, dry_run: false)
    raise ArgumentError, "This batch was already run" unless batch.result.in?(%w[uploaded processing])

    kind = Imports::Kind.for(batch.kind)
    table = Imports::Reader.read(batch.queued_file.download, filename: batch.filename)
    analysis = kind.analyze(table, mapping: batch.mapping.except("resolutions"), options: batch.options, resolutions: batch.mapping["resolutions"] || {})
    created, refused = dry_run ? simulate(kind, analysis, batch, user) : write(kind, analysis, batch, user)

    errors = analysis.errors + refused
    summary = { "created" => created, "refused" => errors.size, "skipped" => analysis.skipped.size, "unknowns" => analysis.unknowns.to_h }
    summary["simulation"] = true if dry_run
    batch.update!(summary: summary, errors_list: errors.map(&:stringify_keys), warnings_list: analysis.skipped.map(&:stringify_keys),
                  lines_read: analysis.read, lines_imported: dry_run ? 0 : created, lines_skipped: analysis.skipped.size,
                  result: !dry_run && (created.positive? || analysis.skipped.any?) ? "imported" : "uploaded")
    audit(batch, user, dry_run)
    batch
  end

  def self.write(kind, analysis, batch, user)
    batch.update_columns(result: "processing")
    created, refused = 0, []
    analysis.items.each_slice(CHUNK) do |items|
      outcome = ApplicationRecord.transaction { kind.write(items, batch: batch, user: user) }
      created += outcome[:created]
      refused += outcome[:refused]
      batch.update_columns(lines_imported: created)
    end
    [ created, refused ]
  end

  def self.simulate(kind, analysis, batch, user)
    outcome = nil
    ApplicationRecord.transaction do
      outcome = kind.write(analysis.items, batch: batch, user: user)
      raise ActiveRecord::Rollback
    end
    [ outcome[:created], outcome[:refused] ]
  end

  def self.audit(batch, user, dry_run)
    return if dry_run

    Accounting::AuditLog.record!(auditable: batch, action: "guided_import", user: user,
                                 payload: { kind: batch.kind, filename: batch.filename, sha256: batch.file_sha256, batch_id: batch.id }.merge(batch.summary.slice("created", "refused", "skipped")))
  end
  private_class_method :write, :simulate, :audit
end
