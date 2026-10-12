# The book balance of the account a batch debits (B01b): the posted entries up to today on the default account of the bank journal. An approximation, said as such on the
# screens: the bank knows better. nil when the journal has no default account.
module Payments::Balance
  def self.of(bank_account)
    account = bank_account.journal.default_account
    return unless account

    Accounting::PostedLine.where(account_id: account.id).where("entry_date <= ?", Date.current).sum("debit - credit")
  end
end
