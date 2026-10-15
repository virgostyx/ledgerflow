# B03c: the verification package of a certificate of the `full` level: a ZIP that `ledger-verify` checks without the application.
#
#   certificate.json        the certificate, signed
#   certificate.pdf         the same, to be read, with the table "proves / does not prove"
#   entries.ndjson          every entry validated up to the instant covered, in the order of validation: its canonical content and its fingerprint
#   anchors.json            the anchors up to the one covered, with the timestamp tokens
#   audit_chain.ndjson      the audit chain: for each event its digest, its metadata and its hashes - never its content
#   accounts.json           the code of each account (to read the totals by class; not attested by the certificate)
#   documents_manifest.json the fingerprint of each supporting document and the entries it is linked to
#   manifest.json           the SHA-256 of each of the files above
#
# It holds accounting data: it travels by a secure channel, optionally encrypted with a passphrase (AES-256-GCM). Deterministic: the same certificate gives the same bytes.
module Integrity::BuildPackage
  Result = Struct.new(:data, :filename, :encrypted, keyword_init: true)

  def self.call(certificate:, passphrase: nil)
    raise ArgumentError, "only a certificate of the full level has a package" unless certificate.disclosure_level == "full"

    files = {
      "certificate.json" => JSON.pretty_generate(certificate.to_document), "certificate.pdf" => Integrity::CertificatePdf.call(certificate),
      "entries.ndjson" => entries(certificate), "anchors.json" => JSON.pretty_generate(anchors(certificate)), "audit_chain.ndjson" => lines(Ledger::AuditChainExport.rows(certificate.entity)),
      "accounts.json" => JSON.pretty_generate(accounts), "documents_manifest.json" => JSON.pretty_generate(documents)
    }
    manifest = { "certificate" => certificate.uuid, "files" => files.sort.map { |path, content| { "path" => path, "sha256" => Digest::SHA256.hexdigest(content.b), "bytes" => content.bytesize } } }
    zip = Accounting::Zipper.build(files.to_a + [ [ "manifest.json", JSON.pretty_generate(manifest) ] ])
    passphrase.present? ? Result.new(data: LedgerVerify::Package.encrypt(zip, passphrase), filename: "ledger-package-#{certificate.uuid}.zip.enc", encrypted: true) : Result.new(data: zip, filename: "ledger-package-#{certificate.uuid}.zip", encrypted: false)
  end

  def self.entries(certificate)
    out = +""
    Accounting::JournalEntry.where(status: Accounting::JournalEntry.ledger_status_values).where("posted_seq <= ?", certificate.through_seq).order(:posted_seq).in_batches(of: 1000) do |batch|
      Ledger::EntryContent.canonical_many(batch.order(:posted_seq).to_a).each do |entry, content|
        out << LedgerVerify::Canonical.generate("id" => entry.id, "content_hash" => entry.content_hash, "entry" => content) << "\n"
      end
    end
    out
  end
  private_class_method :entries

  def self.anchors(certificate)
    Ledger::Anchor.where("number <= ?", certificate.anchor_number).chronological.map do |a|
      { "number" => a.number, "kind" => a.kind, "from_seq" => a.from_seq, "to_seq" => a.to_seq, "entries_count" => a.entries_count, "retroactive_entries" => a.retroactive_entries, "merkle_root" => a.merkle_root,
        "audit_head" => a.audit_head, "audit_length" => a.audit_length, "previous_anchor_hash" => a.previous_anchor_hash, "anchor_hash" => a.anchor_hash, "anchored_at" => a.anchored_at.utc.iso8601(6),
        "timestamp_token" => a.timestamp_token, "timestamp_authority" => a.timestamp_authority, "timestamped_at" => a.timestamped_at&.utc&.iso8601(6) }
    end
  end
  private_class_method :anchors

  def self.accounts = Accounting::Account.order(:id).pluck(:id, :code).map { |id, code| { "id" => id, "code" => code } }
  private_class_method :accounts

  def self.documents
    links = Accounting::DocumentLink.where(target_type: "Accounting::JournalEntry").group(:document_id).pluck(:document_id, Arel.sql("ARRAY_AGG(target_id ORDER BY target_id)")).to_h
    Accounting::Document.order(:id).pluck(:id, :sha256).map { |id, sha| { "id" => id, "sha256" => sha, "entry_ids" => links.fetch(id, []) } }
  end
  private_class_method :documents

  def self.lines(rows) = rows.map { |row| "#{JSON.generate(row)}\n" }.join
  private_class_method :lines
end
