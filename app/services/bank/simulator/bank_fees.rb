# Simulates the bank debiting its own fees (description contains "Fee", which the matcher recognises).
class Bank::Simulator::BankFees
  def self.call(bank_account:, amount: BigDecimal("4.50"), date: Date.current)
    Bank::Simulator::BuildStatement.call(
      iban: bank_account.iban,
      entries: [ { date: date, amount: -BigDecimal(amount.to_s).abs, description: "Account fee #{date.strftime('%m/%Y')}" } ]
    )
  end
end
