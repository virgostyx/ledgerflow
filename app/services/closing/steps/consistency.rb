# Step 13 of the closing (F10): consistency. The checks of R19 run now (they include the invariants I2, I6, I7 and I11 of the year); a blocking anomaly blocks,
# an anomaly that only warns is acknowledged with a comment, one the accountant already acknowledged in R19 does not count.
class Closing::Steps::Consistency < Closing::Step
  self.position = 13
  self.code     = "consistency"
  self.title    = "Consistency"
  self.kind     = :check
  self.blocking = true

  def evaluate
    consistency = Accounting::Consistency::Runner.call(trigger: "closing", fiscal_year: fiscal_year)
    counts = consistency.counts.to_h
    details = { "blocking" => counts["blocking"].to_i, "warning" => counts["warning"].to_i, "acknowledged" => counts["acknowledged"].to_i, "run_id" => consistency.id }
    return blocked(details) if details["blocking"].positive?

    details["warning"].positive? ? warning(details) : ok(details)
  end
end
