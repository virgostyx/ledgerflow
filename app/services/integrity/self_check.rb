# B03c: the check of the integrity of the books, for what direct access to the database could do behind the triggers: recompute the fingerprints of the entries from their
# content, the roots of the anchors from the fingerprints, and the audit chain.
#
#   nightly: the entries validated in the last seven days, and a sample of the rest (a hundredth, rotating: each place that is the residue of the day modulo 100), the chain of anchors
#            and the audit chain;
#   full:    every entry (weekly, and on demand).
#
# A divergence is a blocking anomaly (C23), an alert to the owners and a security event of the company; the same day it is told once.
module Integrity::SelfCheck
  Finding = Struct.new(:part, :subject_id, :message, keyword_init: true)
  Result = Struct.new(:findings, :entries_checked, :mode, :started_at, keyword_init: true) do
    def intact? = findings.empty?
  end

  RECENT = 7.days
  SAMPLE_MODULUS = 100

  def self.call(mode: :nightly, sample: nil)
    started = Time.current
    sample ||= Date.current.yday % SAMPLE_MODULUS
    findings = []
    checked = check_entries(mode, sample, findings)
    anchors = Ledger::AnchorChain.verify(ActsAsTenant.current_tenant)
    findings << Finding.new(part: "anchor", subject_id: anchors.broken_number, message: "Anchor #{anchors.broken_number} does not hold: #{anchors.reason}") unless anchors.intact?
    audit = Accounting::AuditVerifier.call(entity: ActsAsTenant.current_tenant)
    findings << Finding.new(part: "audit_chain", subject_id: audit.broken_id, message: "The audit chain is broken at event #{audit.broken_id}") unless audit.intact?
    Result.new(findings: findings, entries_checked: checked, mode: mode, started_at: started)
  end

  # What the nightly job does for each company that turned the feature on.
  def self.run(mode: :nightly)
    Entity.where(active: true).find_each { |entity| run_for(entity, mode: mode) if entity.feature?(:b03c) }
  end

  # The check of one company, now: recorded, and reported when it found something. => the result
  def self.run_for(entity, mode: :nightly)
    ActsAsTenant.with_tenant(entity) do
      result = call(mode: mode)
      IntegrityCheckRun.create!(mode: mode.to_s, entries_checked: result.entries_checked, findings_count: result.findings.size, started_at: result.started_at, finished_at: Time.current)
      report(entity, result)
      result
    end
  end

  def self.check_entries(mode, sample, findings)
    scope = Accounting::JournalEntry.where.not(content_hash: nil).where.not(posted_seq: nil)
    scope = scope.where("posted_at >= ? OR posted_seq % ? = ?", RECENT.ago, SAMPLE_MODULUS, sample) unless mode == :full
    checked = 0
    scope.in_batches(of: 500) do |batch|
      Ledger::EntryContent.canonical_many(batch.order(:posted_seq).to_a).each do |entry, content|
        checked += 1
        next if Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate(content)) == entry.content_hash

        findings << Finding.new(part: "entry", subject_id: entry.id, message: "Entry #{entry.id} (#{entry.reference}, place #{entry.posted_seq}): its content no longer gives its fingerprint")
      end
    end
    checked
  end
  private_class_method :check_entries

  def self.report(entity, result)
    return if result.intact?

    Accounting::Consistency::Runner.call(trigger: "integrity_self_check", checks: [ Accounting::Consistency::Checks::C23IntegrityCompromised ])
    Accounting::AuditLog.record!(auditable: entity, action: "integrity_divergence_detected", payload: { mode: result.mode, findings: result.findings.map { |f| f.to_h.slice(:part, :subject_id) } })
    UserEntity.owners.where(entity_id: entity.id).includes(:user).find_each do |membership|
      Accounting::Notify.call(user: membership.user, event: "integrity_compromised:#{Date.current}", subject: entity, data: { message: "#{result.findings.size} divergences in the integrity of the books" })
    end
  end
  private_class_method :report
end
