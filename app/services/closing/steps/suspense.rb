# Step 11 of the closing (F10): the suspense and link accounts are at zero (the accounts of the closing settings, 499000 and 580000).
class Closing::Steps::Suspense < Closing::Step
  self.position = 11
  self.code     = "suspense"
  self.title    = "Suspense accounts"
  self.kind     = :check
  self.blocking = true

  CODES = [ Accounting::AccountCodes::TRANSIT, Accounting::AccountCodes::INTERNAL_TRANSFERS ].freeze

  def evaluate
    rows = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: year_end).call.select { |row| CODES.include?(row.code) && !row.balance.zero? }
    accounts = rows.map { |row| { "code" => row.code, "label" => row.label_fr, "balance" => money(row.balance) } }
    accounts.empty? ? ok("accounts" => []) : blocked("accounts" => accounts)
  end
end
