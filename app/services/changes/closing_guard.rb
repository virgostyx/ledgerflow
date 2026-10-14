# B03b: an official export of the report of changes goes out only when the closing is exact (I14). When it is not, the anomaly C21 is recorded in R19 and the answer is false.
module Changes::ClosingGuard
  def self.call(result, fiscal_year:)
    return true if result.closing.balanced?

    Accounting::Consistency::Runner.call(trigger: "changes_report", fiscal_year: fiscal_year, checks: [ Accounting::Consistency::Checks::C21ChangesClosing ])
    false
  end
end
