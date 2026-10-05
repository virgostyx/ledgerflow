require "rails_helper"

RSpec.describe Exports::Backup do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:owner) { create(:user, role: :admin) }
  let!(:journal) { create(:journal, code: "OD", journal_type: :misc) }
  let(:export) { DataExport.create!(user: owner, kind: "backup") }

  before do
    create(:user_entity, :admin, user: owner, entity: entity)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 10, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_440, debit: 0, credit: 10)
    Accounting::PostJournalEntry.call!(entry: entry)
    Accounting::AuditLog.record!(auditable: entity, action: "test_event", user: owner, payload: { "x" => 1 })
  end

  def build!
    described_class.call(data_export: export)
    export.reload
  end

  def unzip(export) = Accounting::Zipper.read(export.file.download)

  it "makes a ZIP of the data, the documents, the audit trail and a manifest, kept a few days (criterion 9)" do
    document = create(:document, name: "Invoice 1.pdf", content: sample_pdf("backup me"))
    build!
    files = unzip(export)

    expect(export).to have_attributes(status: "ready", file_count: files.size - 1)
    expect(export.expires_at).to be_within(1.minute).of(7.days.from_now)
    expect(files.keys).to include("data/entries.csv", "data/entries.json", "data/accounts.csv", "data/partners.csv", "data/journals.csv", "data/vat_codes.csv",
                                  "audit/audit_log.jsonl", "documents/index.csv", "documents/#{document.id}-Invoice_1.pdf", "manifest.json")
    expect(files["documents/#{document.id}-Invoice_1.pdf"]).to eq(document.file.download)
    expect(CSV.parse(files["data/entries.csv"], headers: true).size).to eq(2)
    expect(CSV.parse(files["documents/index.csv"], headers: true).first.to_h).to include("id" => document.id.to_s, "name" => "Invoice 1.pdf", "sha256" => document.sha256)
  end

  it "has a manifest that checks every file, and notices a file that was changed, removed or added" do
    create(:document, content: sample_pdf("one"))
    build!
    manifest = JSON.parse(unzip(export)["manifest.json"])

    expect(manifest).to include("schema_version" => 1)
    expect(manifest["entity"]).to include("id" => entity.id)
    expect(manifest["files"].map { |f| f["path"] }).to match_array(unzip(export).keys - [ "manifest.json" ])
    expect(manifest["files"]).to all(include("sha256" => a_string_matching(/\A\h{64}\z/), "bytes" => be_a(Integer)))
    expect(described_class.verify(export.file.download)).to be_valid

    files = unzip(export)
    tampered = Accounting::Zipper.build(files.merge("data/accounts.csv" => files["data/accounts.csv"] + "999999;Fake\n").except("audit/audit_log.jsonl").merge("extra.txt" => "x"))
    result = described_class.verify(tampered)
    expect(result).not_to be_valid
    expect(result).to have_attributes(mismatches: [ "data/accounts.csv" ], missing: [ "audit/audit_log.jsonl" ], unlisted: [ "extra.txt" ])
  end

  it "carries the audit trail with its hash chain, so that it can be checked elsewhere" do
    build!
    lines = unzip(export)["audit/audit_log.jsonl"].lines.map { |l| JSON.parse(l) }

    expect(lines.map { |l| l["action"] }).to include("test_event")
    expect(lines).to all(include("content_hash", "previous_hash", "created_at", "payload"))
    expect(lines.last["content_hash"]).to eq(Accounting::AuditLog.order(:id).last.content_hash)
  end

  it "holds nothing of another entity" do
    other = create(:entity)
    ActsAsTenant.with_tenant(other) do
      create(:account, code: "999999", label_fr: "Theirs", entity: other)
      create(:document, name: "theirs.pdf")
    end
    build!
    contents = unzip(export)

    expect(contents["data/accounts.csv"]).not_to include("999999")
    expect(contents.keys.grep(/theirs/)).to be_empty
  end

  it "is built by a job, which says when it failed" do
    expect { Exports::BackupJob.perform_now(export.id) }.to change { export.reload.status }.from("processing").to("ready")

    failing = DataExport.create!(user: owner, kind: "backup")
    allow(Exports::Backup).to receive(:call).and_raise("disk full")
    Exports::BackupJob.perform_now(failing.id)
    expect(failing.reload).to have_attributes(status: "failed", error: "disk full")
  end

  it "forgets the old backups: the file goes, the trace stays" do
    build!
    export.update!(expires_at: 1.minute.ago)
    expect { Exports::PurgeExpiredJob.perform_now }.to change { export.reload.status }.from("ready").to("expired")
    expect(export.file).not_to be_attached
  end
end
