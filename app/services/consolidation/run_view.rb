# F12b: one reading of a run for the screens and the exports, whether it is still a draft (what was worked out) or frozen (what was written once).
class Consolidation::RunView
  def initialize(run)
    @run = run
    @data = run.frozen? ? run.snapshot : draft_data
  end

  attr_reader :run

  def members = @data.dig("collection", "members") || @data["members"] || []
  def warnings = @data.dig("collection", "warnings") || @data["warnings"] || []
  def rules = @data["rules"] || {}
  def intragroup = @data["intragroup"] || { "balances" => [], "flows" => [] }
  def minority = @data["minority"] || {}
  def equity_method = @data["equity_method"] || []
  def balance_steps = @data["balance_steps"] || []
  def statements = @data["statements"] || {}
  def difference = @data["difference"]
  def provisional? = @run.provisional
  def entries = @data["entries"] || []

  # [{severity, message}] — the review of a draft; a frozen run had none that blocked.
  def issues = @run.frozen? ? [] : Consolidation::Review.issues(@run).map { |i| { "severity" => i.severity, "message" => i.message } }

  private

  def draft_data
    f = @run.figures
    return {} if f.blank?

    figures = f["figures"].transform_values { |v| BigDecimal(v) }
    f.merge("statements" => Consolidation::Statements::STATEMENTS.index_with { |s| Consolidation::Statements.rows(s, figures).map { |row| row.merge("amount" => row["amount"].to_s("F")) } },
            "entries" => @run.entries.includes(:lines).order(:id).map { |e| { "id" => e.id, "kind" => e.kind, "rule_key" => e.rule_key, "comment" => e.comment, "document_id" => e.document_id,
                                                                                    "lines" => e.lines.order(:id).map { |l| { "statement" => l.statement, "code" => l.code, "side" => l.side, "amount" => l.amount.to_s("F") } } } })
  end
end
