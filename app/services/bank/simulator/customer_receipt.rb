# Simulates a customer paying an invoice. Options build the awkward cases:
# partial/over payment (amount:), no reference (communication: false), duplicate (call twice).
# Other cases (bank fees, unknown transfer) are plain BuildStatement entries.
class Bank::Simulator::CustomerReceipt
  def self.call(invoice:, bank_account:, amount: nil, communication: true, date: Date.current)
    raise ArgumentError, "Invoice ##{invoice.id} is not a customer invoice" unless invoice.customer?
    raise ArgumentError, "Invoice ##{invoice.id} is not posted" unless invoice.posted?

    description = communication ? "Invoice #{invoice.invoice_number} #{comm(invoice)}" : "Transfer"

    Bank::Simulator::BuildStatement.call(
      iban: bank_account.iban,
      entries: [ {
        date:              date,
        amount:            amount || invoice.total_incl_vat,
        description:       description,
        counterparty_name: invoice.partner.name,
        counterparty_iban: invoice.partner.iban
      } ]
    )
  end

  def self.comm(invoice)
    Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(invoice.id))
  end
  private_class_method :comm
end
