require "rails_helper"

RSpec.describe Accounting::VerifyDocument do
  include_context "with entity"

  let(:user)     { create(:user) }
  let(:content)  { sample_pdf("integrity") }
  let(:document) { Accounting::UploadDocument.call(io: StringIO.new(content), filename: "a.pdf", user: user)[:document] }

  def verify(doc = document) = described_class.call(document: doc)

  def audit(action) = Accounting::AuditLog.where(action: action, auditable_id: document.id)

  it "confirms a file that is exactly what was stored, and when it looked" do
    verify

    expect(document.reload).to have_attributes(integrity_status: "ok", integrity_checked_at: be_within(5.seconds).of(Time.current))
  end

  it "detects one bit changed in the stored file" do
    tamper_with_stored_file(document)

    verify

    expect(document.reload.integrity_status).to eq("mismatch")
  end

  it "detects a file that is gone" do
    delete_stored_file(document)

    verify

    expect(document.reload.integrity_status).to eq("missing")
  end

  it "detects a file that was truncated" do
    File.binwrite(stored_path(document), content.byteslice(0, content.bytesize - 10))

    verify

    expect(document.reload.integrity_status).to eq("mismatch")
  end

  it "detects a file replaced by another of the same size" do
    File.binwrite(stored_path(document), "X" * content.bytesize)

    verify

    expect(document.reload.integrity_status).to eq("mismatch")
  end

  it "does not change the document, nor its file, nor its checksum" do
    verify
    tamper_with_stored_file(document)
    stored = File.binread(stored_path(document))

    verify

    expect(document.reload.sha256).to eq(Digest::SHA256.hexdigest(content))
    expect(File.binread(stored_path(document))).to eq(stored)
  end

  it "says what it found" do
    expect(verify).to have_attributes(success?: true)
    expect(verify[:status]).to eq("ok")
    tamper_with_stored_file(document)
    expect(verify[:status]).to eq("mismatch")
  end

  it "works on a document frozen by a validated entry, and on an archived one" do
    Accounting::LinkDocument.call(document: document, target: create(:journal_entry, :posted), user: user)
    document.update!(status: :archived)
    tamper_with_stored_file(document)

    expect { verify }.not_to raise_error

    expect(document.reload.integrity_status).to eq("mismatch")
  end

  describe "the audit trail" do
    it "records a failure, once, with what was expected and what was found" do
      tamper_with_stored_file(document)

      verify
      verify

      row = audit("document_integrity_failed").sole
      expect(row.payload).to include("status" => "mismatch", "expected" => document.sha256, "found" => a_string_matching(/\A\h{64}\z/))
      expect(row.user_id).to be_nil
    end

    it "records that the file is back when it is restored" do
      tamper_with_stored_file(document)
      verify
      restore_stored_file(document, content)

      verify

      expect(document.reload.integrity_status).to eq("ok")
      expect(audit("document_integrity_restored").count).to eq(1)
    end

    it "records nothing for a file that is fine" do
      verify

      expect(audit("document_integrity_failed")).to be_empty
    end
  end
end
