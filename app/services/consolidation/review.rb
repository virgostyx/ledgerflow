# F12b step 6, the review: what blocks a run and what only warns. Nothing blocks silently and nothing is left out: a run with a blocking issue cannot be
# validated, so cannot be frozen. Provisional figures (an open year, another closing date) warn and are marked as such on every export.
module Consolidation::Review
  Issue = Struct.new(:severity, :message, keyword_init: true)

  def self.issues(run)
    f = run.figures
    return [ Issue.new(severity: "blocking", message: "The run has not been worked out yet.") ] if f.blank?

    collection = f.fetch("collection")
    issues = collection.fetch("errors").map { |m| Issue.new(severity: "blocking", message: m) }
    issues += collection.fetch("warnings").map { |m| Issue.new(severity: "warning", message: m) }
    issues << Issue.new(severity: "blocking", message: "A member joined or left during the period: the proportion of the period is not handled, nothing is consolidated until that rule exists and is validated.") if collection.dig("facts", "scope_change")
    f.fetch("rules").each do |key, state|
      issues << Issue.new(severity: "blocking", message: "#{Consolidation::Rules.fetch(key)[:title]} is needed (#{Consolidation::Rules.fetch(key)[:needed_for]}) and no accountant's validation of the rule is recorded.") if state["state"] == "not_validated"
    end
    unexplained(f).each { |row, remaining| issues << Issue.new(severity: "blocking", message: unexplained_message(row, remaining)) }
    f.fetch("balance_steps").each { |step| issues << Issue.new(severity: "blocking", message: "The consolidated balance sheet is out of balance by #{step['difference']} after: #{step['label']}.") if BigDecimal(step["difference"]).nonzero? }
    issues << Issue.new(severity: "warning", message: "The rules without a validation use the proposals of the application, shown for information: #{f['defaults_used'].join(', ')}.") if f["defaults_used"].present? && f["intragroup"].values.flatten.any?
    issues
  end

  def self.blocking(run) = issues(run).select { |i| i.severity == "blocking" }

  # [[row, what remains to explain]] of the intragroup comparisons whose difference no adjustment entry covers.
  def self.unexplained(figures)
    figures.fetch("intragroup").values.flatten.filter_map do |row|
      difference = BigDecimal(row["difference"]).abs
      next if difference.zero?

      covered = figures.fetch("adjustments").select { |a| same_pair?(a["context"], row) }.sum(BigDecimal("0")) { |a| BigDecimal(a["total"]) }
      remaining = difference - covered
      [ row, remaining ] if remaining.positive?
    end
  end

  def self.same_pair?(context, row)
    # (a context that comes from a form holds strings: compared as text)
    %w[kind creditor_id debtor_id heading_creditor heading_debtor].all? { |key| context[key].to_s == row[key].to_s }
  end

  def self.unexplained_message(row, remaining)
    what = row["kind"] == "balances" ? "receivable of #{row['creditor']} (#{row['amount_creditor']}) and payable of #{row['debtor']} (#{row['amount_debtor']})" : "sales of #{row['creditor']} (#{row['amount_creditor']}) and purchases of #{row['debtor']} (#{row['amount_debtor']})"
    "Intragroup difference of #{format('%.2f', remaining)} between the #{what}: record an adjustment entry that explains it."
  end
end
