# F12b: what a frozen run changes with respect to the one it replaces: the headings whose amount moved, the members that came or went, and the entries.
module Consolidation::Diff
  # => { headings: [{code, label, previous, current, delta}], members_added:, members_removed:, entries: {previous:, current:} } or nil when there is no earlier run
  def self.call(run)
    previous = run.previous_run
    return unless run.frozen? && previous&.frozen?

    now, before = run.snapshot, previous.snapshot
    headings = now["statements"].flat_map do |statement, rows|
      rows.filter_map do |row|
        old = before.dig("statements", statement)&.find { |r| r["code"] == row["code"] }&.fetch("amount") || "0.0"
        delta = BigDecimal(row["amount"]) - BigDecimal(old)
        { "statement" => statement, "code" => row["code"], "label" => row["label"], "previous" => old, "current" => row["amount"], "delta" => delta.to_s("F") } if delta.nonzero?
      end
    end
    names = ->(snapshot) { snapshot["members"].map { |m| m["name"] } }
    { "previous_run_id" => previous.id, "headings" => headings, "members_added" => names.(now) - names.(before), "members_removed" => names.(before) - names.(now),
      "entries" => { "previous" => before["entries"].size, "current" => now["entries"].size } }
  end
end
