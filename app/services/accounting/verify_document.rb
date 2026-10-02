# Recomputes the SHA-256 of a stored file and compares it with what was recorded at upload (F03). One bit changed, a
# truncated or replaced file, or a file that is gone is detected. The file is read as a stream, never changed; the
# result (ok, mismatch, missing) and the time go on the document (derived data: written even if the document is
# frozen). A failure is audited once, and so is the file coming back. An error of the storage itself (unreachable)
# is raised, never taken for a missing file.
class Accounting::VerifyDocument
  def self.call(document:) = new(document).call

  def initialize(document)
    @document = document
  end

  def call
    status, found = compute
    previous = @document.integrity_status
    @document.update_columns(integrity_status: status, integrity_checked_at: Time.current)
    audit(status, previous, found)
    LightService::Context.make(document: @document, status: status)
  end

  private

  def compute
    digest = Digest::SHA256.new
    size = 0
    @document.file.blob.download do |chunk|
      digest << chunk
      size += chunk.bytesize
    end
    found = digest.hexdigest
    [ found == @document.sha256 && size == @document.byte_size ? "ok" : "mismatch", found ]
  rescue ActiveStorage::FileNotFoundError
    [ "missing", nil ]
  end

  def audit(status, previous, found)
    if status != "ok" && previous != status
      Accounting::AuditLog.record!(auditable: @document, action: "document_integrity_failed", payload: { status: status, expected: @document.sha256, found: found })
    elsif status == "ok" && %w[mismatch missing].include?(previous)
      Accounting::AuditLog.record!(auditable: @document, action: "document_integrity_restored", payload: { was: previous })
    end
  end
end
