# Simulates one customer transfer settling several open invoices, naming their numbers in the description.
class Bank::Simulator::GroupedReceipt
  def self.call(invoices:, bank_account:, date: Date.current)
    raise ArgumentError, "Grouped receipt needs at least two invoices" if invoices.size < 2
    raise ArgumentError, "Invoices must be open customer invoices" unless invoices.all? { |i| i.customer? && i.posted? }
    raise ArgumentError, "Invoices must belong to the same partner" unless invoices.map(&:partner_id).uniq.one?

    partner = invoices.first.partner
    Bank::Simulator::BuildStatement.call(
      iban: bank_account.iban,
      entries: [ {
        date:              date,
        amount:            invoices.sum(&:remaining_amount),
        description:       "Invoices #{invoices.map(&:invoice_number).join(' and ')}",
        counterparty_name: partner.name,
        counterparty_iban: partner.iban
      } ]
    )
  end
end
