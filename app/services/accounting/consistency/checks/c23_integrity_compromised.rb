# The integrity of the books is compromised (B03c): an entry no longer gives its fingerprint, an anchor no longer follows from the entries it binds, or the audit chain does not
# hold. Found by `Integrity::SelfCheck` (the entries of the last seven days and a sample of the rest, the chain of anchors, the audit chain); a certificate is not issued while
# this stands.
class Accounting::Consistency::Checks::C23IntegrityCompromised < Accounting::Consistency::Check
  self.check_id = "C23"
  self.severity = "blocking"
  self.title = "The integrity of the books is compromised"

  def call
    entity = ActsAsTenant.current_tenant
    Integrity::SelfCheck.call(mode: :nightly).findings.map do |found|
      subject = found.part == "entry" ? (Accounting::JournalEntry.find_by(id: found.subject_id) || entity) : entity
      finding(subject: subject, message: found.message, part: found.part, broken: found.subject_id)
    end
  end
end
