# B03c: issues a certificate of integrity. Who may (`integrity.issue`) is the caller's to check; the service needs a second factor given recently, a company that turned the
# feature on, and an active signing key.
#
# The instant covered is now (an anchor is made for it) or the bound of an anchor already made (`anchor_number`): nothing in between can be certified. It is refused, with a
# blocking anomaly in R19, when the audit chain, the chain of anchors, I1 or I2 do not hold; any other failure is a reservation, at the head of the certificate. What is signed is
# the canonical JSON (RFC 8785) of the certificate, and it is stored as it was signed.
#
# => the context: `certificate`, or a failure with the reason
class Integrity::IssueCertificate
  PROVES = [
    "That the set of entries validated up to the instant covered corresponds to a precise cryptographic fingerprint, computed at earlier moments and chained.",
    "That the audit trail is intact and tied to those entries.",
    "That the accounting invariants listed held when the certificate was issued.",
    "With an external timestamp: that these fingerprints existed at the date of the timestamp.",
    "That the certificate was issued by this instance of LedgerFlow (signature)."
  ].freeze
  DOES_NOT_PROVE = [
    "That the entries are accurate, complete or compliant with the regulations.",
    "That the supporting documents are authentic (only that they have not changed since they were uploaded).",
    "An audit opinion, or the opinion of a chartered accountant.",
    "That nothing was omitted before the anchoring began (the earlier history is covered by a retroactive anchor, said so on any certificate that covers it).",
    "Without an external timestamp: protection against an operator who holds both the database and the signing key.",
    "The changes of the reference data shared by all companies (such as the VAT codes), which are written in no company's audit chain."
  ].freeze

  # What stops the issue, whatever else is true.
  REFUSING = %w[I1 I2 I17].freeze

  def self.call(user:, recent_second_factor:, disclosure:, recipient: nil, fiscal_year: nil, anchor_number: nil) = new(user, recent_second_factor, disclosure, recipient, fiscal_year, anchor_number).call

  def initialize(user, recent_second_factor, disclosure, recipient, fiscal_year, anchor_number)
    @user = user
    @second_factor = recent_second_factor
    @disclosure = disclosure.to_s
    @recipient = recipient.presence
    @fiscal_year = fiscal_year
    @anchor_number = anchor_number
    @entity = ActsAsTenant.current_tenant
  end

  def call
    ctx = LightService::Context.make(certificate: nil)
    return fail_with(ctx, I18n.t("integrity.errors.second_factor")) unless @second_factor
    return fail_with(ctx, I18n.t("integrity.errors.disclosure")) unless IntegrityCertificate::DISCLOSURES.include?(@disclosure)

    ApplicationRecord.transaction do
      raise Ledger::SigningKeys::NoActiveKey, "no active signing key" unless Ledger::SigningKey.exists?(status: "active")

      anchor = anchor_to_cover or return fail_with(ctx, I18n.t("integrity.errors.no_anchor"))
      health = health_of(anchor)
      refusal = refusal_for(health)
      return refuse(ctx, refusal) if refusal

      ctx[:certificate] = issue(anchor, health)
    end
    ctx
  rescue Ledger::SigningKeys::NoActiveKey, Ledger::SigningKeys::PrivateKeyMissing, Ledger::SigningKeys::NotConfigured => e
    fail_with(LightService::Context.make(certificate: nil), I18n.t("integrity.errors.no_key", reason: e.message))
  rescue Ledger::Anchoring::Refused => e
    refuse(LightService::Context.make(certificate: nil), I18n.t("integrity.errors.anchoring", reason: e.message))
  end

  private

  def fail_with(ctx, message) = ctx.tap { |c| c.fail!(message) }

  def refuse(ctx, message)
    Accounting::Consistency::Runner.call(trigger: "integrity_certificate", checks: [ Accounting::Consistency::Checks::C23IntegrityCompromised, Accounting::Consistency::Checks::C01UnbalancedEntry,
                                                                                      Accounting::Consistency::Checks::C11Invariants ])
    fail_with(ctx, message)
  end

  def anchor_to_cover
    return Ledger::Anchor.find_by(number: @anchor_number) if @anchor_number

    anchor = Ledger::Anchoring.call(kind: "on_demand") || Ledger::Anchor.chronological.last
    Ledger::Timestamping.call(anchor) if anchor # best effort: an authority that does not answer is told in the certificate, it does not stop it
    anchor
  end

  Health = Struct.new(:audit, :anchors, :invariants, keyword_init: true)

  def health_of(_anchor)
    anchors = Ledger::AnchorChain.verify(@entity)
    Health.new(audit: Accounting::AuditVerifier.call(entity: @entity), anchors: anchors, invariants: Integrity::Invariants.call(anchors: anchors))
  end

  def refusal_for(health)
    return I18n.t("integrity.errors.audit_chain", event: health.audit.broken_id) unless health.audit.intact?
    return I18n.t("integrity.errors.anchor_chain", anchor: health.anchors.broken_number, reason: health.anchors.reason) unless health.anchors.intact?

    failing = (Integrity::IssueCertificate::REFUSING & health.invariants.select { |_, v| v["status"] == "fails" }.keys)
    I18n.t("integrity.errors.invariant", invariants: failing.join(", ")) if failing.any?
  end

  def issue(anchor, health)
    uuid = SecureRandom.uuid
    body = LedgerVerify::Canonical.generate(document(anchor, health, uuid))
    key_id, signature = Ledger::SigningKeys.sign(body)
    certificate = IntegrityCertificate.create!(uuid: uuid, issued_by: @user, fiscal_year: @fiscal_year, covered_at: anchor.anchored_at, through_seq: anchor.to_seq, anchor_number: anchor.number,
                                              disclosure_level: @disclosure, recipient_label: @recipient, payload: JSON.parse(body), body: body, key_id: key_id, signature: signature)
    Accounting::AuditLog.record!(auditable: certificate, action: "integrity_certificate_issued", user: @user, payload: { uuid: uuid, disclosure: @disclosure, covered_at: anchor.anchored_at.utc.iso8601(6), anchor: anchor.number })
    certificate
  end

  def document(anchor, health, uuid)
    key = Ledger::SigningKey.find_by!(status: "active")
    stats = statistics(anchor.to_seq)
    reservations = reservations_for(anchor, health, stats)
    doc = {
      "type" => "ledgerflow-integrity-certificate", "version" => 1, "id" => uuid, "issued_at" => Time.current.utc.iso8601(6), "covered_at" => anchor.anchored_at.utc.iso8601(6),
      "company" => { "id" => @entity.id, "name" => @entity.legal_name }, "scope" => { "fiscal_year" => @fiscal_year&.year, "fiscal_year_id" => @fiscal_year&.id }, "disclosure" => @disclosure, "recipient" => @recipient,
      "coverage" => coverage(anchor, stats),
      "invariants" => health.invariants, "audit_chain" => audit_chain(health.audit), "documents" => documents_state, "locked_periods" => locked_periods,
      "blocking_anomalies" => blocking_anomalies, "witnesses" => { "divergences" => TimeTravel::WitnessCheck.call(fiscal_year: nil).size },
      "software" => Integrity::SoftwareManifest.call, "retroactive" => { "covers" => anchor_retroactive?(anchor), "entries" => retroactive_entries(anchor) },
      "timestamp" => timestamp_state(anchor), "reservations" => reservations, "proves" => PROVES, "does_not_prove" => DOES_NOT_PROVE,
      "public_key" => { "key_id" => key.key_id, "algorithm" => key.algorithm, "public_key" => key.public_key, "fingerprint" => key.fingerprint },
      "verification_path" => "/verify/#{uuid}", "package" => { "included" => @disclosure == "full" }
    }
    doc["totals"] = totals(anchor.to_seq) unless @disclosure == "minimal"
    doc
  end

  def coverage(anchor, stats)
    base = { "through_seq" => anchor.to_seq, "entries" => stats[:entries], "anchors" => { "from" => 1, "to" => anchor.number, "last_anchor_hash" => anchor.anchor_hash, "last_merkle_root" => anchor.merkle_root } }
    @disclosure == "minimal" ? base : base.merge("lines" => stats[:lines])
  end

  def ledger_lines(through_seq)
    scope = Accounting::JournalEntryLine.joins(:journal_entry).where(accounting_journal_entries: { status: Accounting::JournalEntry.ledger_status_values }).where("accounting_journal_entries.posted_seq <= ?", through_seq)
    @fiscal_year ? scope.where(accounting_journal_entries: { fiscal_year_id: @fiscal_year.id }) : scope
  end

  def statistics(through_seq)
    entries = Accounting::JournalEntry.where(status: Accounting::JournalEntry.ledger_status_values).where("posted_seq <= ?", through_seq)
    entries = entries.where(fiscal_year_id: @fiscal_year.id) if @fiscal_year
    { entries: entries.count, lines: ledger_lines(through_seq).count }
  end

  def totals(through_seq)
    lines = ledger_lines(through_seq)
    debit, credit = lines.pick(Arel.sql("COALESCE(SUM(accounting_journal_entry_lines.debit), 0)"), Arel.sql("COALESCE(SUM(accounting_journal_entry_lines.credit), 0)"))
    by_class = lines.joins(:account).group(Arel.sql("LEFT(accounting_accounts.code, 1)"))
                    .pluck(Arel.sql("LEFT(accounting_accounts.code, 1)"), Arel.sql("SUM(accounting_journal_entry_lines.debit)"), Arel.sql("SUM(accounting_journal_entry_lines.credit)"))
    { "debit" => money(debit), "credit" => money(credit), "by_class" => by_class.sort.to_h { |klass, d, c| [ klass, { "debit" => money(d), "credit" => money(c) } ] } }
  end

  def money(value) = Ledger::EntryContent.send(:decimal, value, 2)

  def audit_chain(audit)
    chained = Accounting::AuditLog.unscoped.where(entity_id: @entity.id).where.not(content_hash: nil)
    { "intact" => audit.intact?, "head" => chained.order(:id).last&.content_hash, "length" => audit.count, "version_1_events" => audit.version_1, "unchained_events" => audit.unchained }
  end

  def documents_state
    documents = Accounting::Document.all
    { "mismatch" => documents.where(integrity_status: "mismatch").count, "missing" => documents.where(integrity_status: "missing").count, "last_check" => documents.maximum(:integrity_checked_at)&.utc&.iso8601 }
  end

  def locked_periods = Accounting::PeriodLock.in_force.order(:starts_on).map { |lock| { "kind" => lock.kind, "starts_on" => lock.starts_on.iso8601, "ends_on" => lock.ends_on.iso8601 } }

  def blocking_anomalies
    run = Accounting::ConsistencyRun.order(:started_at, :id).last or return 0
    acknowledged = Accounting::ConsistencyAcknowledgement.pluck(:fingerprint)
    Accounting::ConsistencyFinding.where(run_id: run.id, severity: "blocking").where.not(fingerprint: acknowledged).count
  end

  # none: no authority; pending: one is configured and the last anchor has no token yet; granted: the last anchor has its token.
  def timestamp_state(anchor)
    return { "status" => "none" } unless Ledger::Timestamping.configured?(@entity)
    return { "status" => "pending", "anchors" => anchor.number, "anchors_timestamped" => Ledger::Anchor.where("number <= ?", anchor.number).where.not(timestamp_token: nil).count } if anchor.timestamp_token.blank?

    { "status" => "granted", "authority" => anchor.timestamp_authority, "timestamped_at" => anchor.timestamped_at.utc.iso8601, "anchors" => anchor.number,
      "anchors_timestamped" => Ledger::Anchor.where("number <= ?", anchor.number).where.not(timestamp_token: nil).count }
  end

  def anchor_retroactive?(anchor) = retroactive_entries(anchor).positive?

  # Entries covered that were fingerprinted afterwards, in all the anchors up to this one.
  def retroactive_entries(anchor) = Ledger::Anchor.where("number <= ?", anchor.number).sum(:retroactive_entries)

  def reservations_for(anchor, health, stats)
    list = []
    list << "No external timestamp: the proof rests on the signing key of this instance alone." if timestamp_state(anchor)["status"] == "none"
    list << "The timestamp of the last anchor was not obtained yet (the authority did not answer): until it is, nothing outside this instance proves the date." if timestamp_state(anchor)["status"] == "pending"
    list << "The books covered include #{retroactive_entries(anchor)} entries validated before the anchoring began (retroactive anchor): their history before it is not proved." if anchor_retroactive?(anchor)
    health.invariants.each { |id, result| list << "Invariant #{id} does not hold: #{result['detail']}" if result["status"] == "fails" && !REFUSING.include?(id) }
    list << "#{blocking_anomalies} blocking anomalies are open in the consistency checks." if blocking_anomalies.positive?
    docs = documents_state
    list << "#{docs['mismatch'] + docs['missing']} supporting documents do not match their recorded checksum or are missing." if (docs["mismatch"] + docs["missing"]).positive?
    list << "#{health.audit.version_1} audit events were written before the version 2 of the chain: only their links can be verified from outside." if health.audit.version_1.positive?
    list << "#{health.audit.unchained} audit events are not part of the chain." if health.audit.unchained.positive?
    divergences = TimeTravel::WitnessCheck.call(fiscal_year: nil).size
    list << "#{divergences} frozen snapshots are not reproduced by the history of the books." if divergences.positive?
    list << "No entry was validated yet." if stats[:entries].zero?
    list
  end
end
