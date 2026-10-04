# Step 14 of the closing (F10): the analytical review. R07 and R08 against N-1: each heading that moved by more than the entity's thresholds (20 % and 1 000 EUR
# by default) carries a comment. Does not block; pending until every heading flagged is commented, and the comments are kept on the step.
class Closing::Steps::AnalyticalReview < Closing::Step
  self.position = 14
  self.code     = "analytical_review"
  self.title    = "Analytical review"
  self.kind     = :report
  self.blocking = false

  def evaluate
    flagged = flagged_rows
    comments = stored_comments.slice(*flagged.map { |f| f["code"] })
    details = { "flagged" => flagged, "comments" => comments, "comparability" => comparability }.compact
    flagged.all? { |f| comments.key?(f["code"]) } ? ok(details) : pending(details)
  end

  def comment(user:, code:, text:)
    ctx = LightService::Context.make(step: row)
    return ctx.tap { |c| c.fail!("A comment is needed.") } if text.to_s.strip.blank?
    return ctx.tap { |c| c.fail!("This heading is not one to comment.") } unless flagged_rows.any? { |f| f["code"] == code }

    comments = stored_comments.merge(code => { "text" => text.to_s.strip, "by" => user.id, "at" => Time.current.iso8601 })
    row.update!(result: row.result.merge("comments" => comments))
    ctx
  end

  private

  def row = run.steps.find_by(code: self.class.code)
  def stored_comments = row&.result&.fetch("comments", nil) || {}

  # The headings of the balance sheet and the income statement, with N-1, that moved enough. A heading that was empty last year counts as moved by its whole amount.
  def flagged_rows
    entity = run.entity
    report = Accounting::AnnualAccounts.new(fiscal_year: fiscal_year).call
    return [] unless report.previous_year

    Accounting::AnnualAccounts::STATEMENTS.flat_map { |statement| report.rows(statement) }.filter_map do |r|
      variation = r.variation_amount
      next if variation.nil? || variation.abs <= entity.review_threshold_amount
      next unless r.previous.zero? || (variation.abs / r.previous.abs * 100) > entity.review_threshold_pct

      { "code" => r.code, "label" => r.label, "amount" => money(r.amount), "previous" => money(r.previous), "variation" => money(variation) }
    end
  end

  def comparability
    previous = Accounting::AnnualAccounts.new(fiscal_year: fiscal_year).call.previous_year
    return unless previous

    months = ->(fy) { (fy.end_date.year * 12 + fy.end_date.month) - (fy.start_date.year * 12 + fy.start_date.month) + 1 }
    "The years do not have the same length (#{months.(fiscal_year)} and #{months.(previous)} months): the variations are not comparable." if months.(fiscal_year) != months.(previous)
  end
end
