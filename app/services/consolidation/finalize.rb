# F12b: validating and freezing a run (the owner's: `consolidation.approve`). Validating works the run out again and refuses it when anything blocks. Freezing refuses a run
# whose sources changed since it was validated, then writes its content once, with its SHA-256, and links it to the run it replaces. A frozen run never changes.
module Consolidation::Finalize
  class Refused < StandardError; end

  def self.validate!(run, user)
    raise Refused, "only a draft run is validated" unless run.draft?

    Consolidation::Compute.call(run)
    blocking = Consolidation::Review.blocking(run)
    raise Refused, blocking.map(&:message).join(" ") if blocking.any?

    run.update!(status: "validated", validated_by: user, validated_at: Time.current)
    run
  end

  def self.freeze!(run, user)
    raise Refused, "only a validated run is frozen" unless run.validated?
    raise Refused, "the books of a member changed since the run was validated: work it out and validate it again" if stale?(run)

    previous = run.group.runs.where(status: "frozen").where.not(id: run.id).order(:frozen_at, :id).last
    content = snapshot_of(run)
    run.update!(status: "frozen", frozen_by: user, frozen_at: Time.current, snapshot: content, snapshot_sha256: Consolidation::Run.fingerprint(content), previous_run: previous, figures: {})
    run
  end

  def self.stale?(run)
    Consolidation::Compute.source_digest(Consolidation::Collect.call(run.group, run.reporting_date)) != run.figures["source_digest"]
  end

  def self.snapshot_of(run)
    f = run.figures
    group = run.group
    figures = f["figures"]
    { "group" => { "id" => group.id, "name" => group.name, "currency" => group.currency, "parent" => { "id" => group.entity_id, "name" => group.entity.name } },
      "reporting_date" => run.reporting_date.iso8601, "provisional" => run.provisional,
      "members" => f.dig("collection", "members").map { |m| m.merge("stakes" => group.members.find(m["member_id"]).stakes.map { |s| { "on" => s.effective_on.iso8601, "percentage" => s.percentage.to_s("F") } }) },
      "warnings" => f.dig("collection", "warnings"), "rules" => f["rules"], "intragroup" => f["intragroup"], "adjustments" => f["adjustments"],
      "entries" => run.entries.includes(:lines).order(:id).map { |e| { "id" => e.id, "kind" => e.kind, "rule_key" => e.rule_key, "comment" => e.comment, "document_id" => e.document_id, "context" => e.context,
                                                                          "lines" => e.lines.order(:id).map { |l| { "statement" => l.statement, "code" => l.code, "side" => l.side, "amount" => l.amount.to_s("F") } } } },
      "balance_steps" => f["balance_steps"], "cumul" => f["cumul"], "minority" => f["minority"], "equity_method" => f["equity_method"],
      "statements" => Consolidation::Statements::STATEMENTS.index_with { |s| Consolidation::Statements.rows(s, figures.transform_values { |v| BigDecimal(v) }).map { |row| row.merge("amount" => row["amount"].to_s("F")) } },
      "difference" => f["difference"] }
  end
end
