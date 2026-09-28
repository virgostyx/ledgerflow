# Runs every registered check for the current entity, stores the run and its findings, and warns the
# entity's administrators of blocking anomalies that were not there in the previous run and are not
# acknowledged. A check that raises is recorded on the run and never stops the others.
class Accounting::Consistency::Runner
  def self.call(trigger: "manual")
    started = Time.current
    run = Accounting::ConsistencyRun.create!(trigger: trigger, started_at: started)
    errors = {}
    findings = Accounting::Consistency::Check.registry.flat_map do |check|
      check.new.call
    rescue StandardError => e
      Rails.logger.error("[Consistency] #{check.check_id}: #{e.class}: #{e.message}")
      errors[check.check_id] = "#{e.class}: #{e.message}"
      []
    end

    previous = previous_fingerprints(run)
    acknowledged = Accounting::ConsistencyAcknowledgement.pluck(:fingerprint).to_set
    rows = findings.map do |f|
      f.to_h.slice(:check_id, :severity, :subject_type, :subject_id, :message, :data, :fingerprint)
       .merge(run_id: run.id, entity_id: run.entity_id, created_at: started, updated_at: started)
    end
    Accounting::ConsistencyFinding.insert_all(rows) if rows.any?

    open = findings.reject { |f| acknowledged.include?(f.fingerprint) }
    run.update!(finished_at: Time.current, duration_ms: ((Time.current - started) * 1000).to_i, errors_by_check: errors,
                counts: Accounting::ConsistencyFinding::SEVERITIES.index_with { |s| open.count { |f| f.severity == s } }
                                                                   .merge("acknowledged" => findings.size - open.size))
    notify(run, open.select { |f| f.severity == "blocking" && previous.exclude?(f.fingerprint) })
    run
  end

  def self.previous_fingerprints(run)
    last = Accounting::ConsistencyRun.where.not(id: run.id).order(:started_at, :id).last
    last ? Accounting::ConsistencyFinding.where(run_id: last.id).pluck(:fingerprint).to_set : Set.new
  end

  def self.notify(run, new_blocking)
    return if new_blocking.empty?

    recipients = User.joins(:user_entities).where(user_entities: { entity_id: run.entity_id, role: UserEntity.roles[:admin], active: true })
    recipients.find_each { |user| Accounting::ConsistencyMailer.blocking_findings(user, run, new_blocking.size).deliver_later }
  end

  private_class_method :previous_fingerprints, :notify
end
