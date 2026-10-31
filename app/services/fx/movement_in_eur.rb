# The euro value of a movement on a foreign account: the bank knows only its own currency, the books are in euros. The amount converted at the rate the
# entity's policy gives for the date of the movement; nil for a movement in euros, and nil when no rate is known for that date (never another one).
module Fx::MovementInEur
  def self.call(transaction)
    return if transaction.currency == "EUR"

    Fx::Convert.to_eur(transaction.amount.abs, Fx::RateFor.call(transaction.currency, document_date: transaction.transaction_date))
  rescue Fx::MissingRate
    nil
  end
end
