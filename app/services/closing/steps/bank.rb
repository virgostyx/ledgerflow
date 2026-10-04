# Step 3 of the closing (F10): the bank. Each active bank account has its reconciliation frozen (R06) on the last day of the year, and it still has no gap
# today: what was frozen is not trusted when the books have moved since.
class Closing::Steps::Bank < Closing::Step
  self.position = 3
  self.code     = "bank"
  self.title    = "Bank"
  self.kind     = :check
  self.blocking = true

  def evaluate
    accounts = Accounting::BankAccount.where(active: true).order(:id).map { |account| read(account) }
    details = { "accounts" => accounts }
    accounts.all? { |a| a["frozen"] && a["gap_now"].to_d.zero? } ? ok(details) : blocked(details)
  end

  private

  def read(account)
    frozen = Accounting::BankReconciliationReport.where(bank_account: account, as_of: year_end).exists?
    gap = Accounting::BankReconciliationQuery.new(bank_account: account, as_of: year_end).call.gap
    { "id" => account.id, "label" => account.label_fr, "frozen" => frozen, "gap_now" => money(gap) }
  end
end
