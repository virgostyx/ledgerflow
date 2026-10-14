# The books at the closing (F10) as numbers (strings, so that the JSON is the same whatever reads it): the trial balance, the balance sheet and the income statement.
# known_at (B03a): the same, as the books were known at that instant; the witness check recomputes a frozen snapshot with it.
module Closing::SnapshotContent
  def self.call(fiscal_year:, known_at: nil)
    year_end = fiscal_year.end_date
    rows = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: year_end, known_at: known_at).call
    report = Accounting::AnnualAccounts.new(fiscal_year: fiscal_year, known_at: known_at).call
    figures = ->(statement) { report.rows(statement).map { |r| { "code" => r.code, "label" => r.label, "amount" => money(r.amount), "previous" => r.previous && money(r.previous) } } }
    {
      "fiscal_year" => { "year" => fiscal_year.year, "start_date" => fiscal_year.start_date.to_s, "end_date" => year_end.to_s },
      "trial_balance" => rows.map { |r| { "code" => r.code, "label" => r.label_fr, "debit" => money(r.total_debit), "credit" => money(r.total_credit) } },
      "balance_sheet" => { "assets" => figures.(:assets), "liabilities" => figures.(:liabilities) },
      "income_statement" => figures.(:income)
    }
  end

  def self.money(value) = value.to_d.to_s("F")
end
