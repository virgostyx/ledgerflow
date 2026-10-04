# Step 4 of the closing (F10): the partners. No balanced group of open lines left unlettered (R05), and the aged balance (R04) is the balance of the accounts
# 400 and 440 (I4), for customers and for suppliers.
class Closing::Steps::Partners < Closing::Step
  self.position = 4
  self.code     = "partners"
  self.title    = "Partners"
  self.kind     = :check
  self.blocking = true

  def evaluate
    groups = Accounting::UnletteredLinesQuery.new(kind: :both, as_of: year_end).balanced_unlettered_groups.size
    gaps = { customer: Accounting::AccountCodes::CUSTOMERS, supplier: Accounting::AccountCodes::SUPPLIERS }.filter_map { |kind, code| gap(kind, code) }
    details = { "balanced_groups" => groups, "aged_balance_gaps" => gaps }
    groups.positive? || gaps.any? ? blocked(details) : ok(details)
  end

  private

  # The aged balance against the balance of the collective account (I4): nil when they agree.
  def gap(kind, code)
    aged = Accounting::AgedBalanceQuery.totals(Accounting::AgedBalanceQuery.new(kind: kind, as_of: year_end).call).total
    account = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: year_end).call.find { |row| row.code == code }&.balance || BigDecimal("0")
    return if aged == account

    { "kind" => kind.to_s, "code" => code, "aged_balance" => money(aged), "account" => money(account) }
  end
end
