# A stored document whose file no longer matches the checksum recorded at upload, or is gone (F03, `documents:verify`).
class Accounting::Consistency::Checks::C18DocumentIntegrity < Accounting::Consistency::Check
  self.check_id = "C18"
  self.severity = "blocking"
  self.title = "A stored document no longer matches its checksum"

  def call
    Accounting::Document.where(integrity_status: %w[mismatch missing]).order(:id).map do |document|
      finding(subject: document, message: "#{document.name}: #{document.integrity_status} (recorded checksum #{document.sha256.first(12)}…)",
              status: document.integrity_status, sha256: document.sha256)
    end
  end
end
