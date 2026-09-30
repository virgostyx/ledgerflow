# How an invoice was settled, for the auditor: for each payment, the value date, the bank reference and the amount really
# paid for THIS invoice. Sources, most precise first: payment lines linked to the invoice (customer receipts), partial
# allocations on its payable/receivable line, executed SEPA payment batches, the total lettering. Each is resolved to the
# bank transaction booked in the same entry when there is one (value date, reference, movement amount and currency);
# otherwise to the entry itself. Nothing at all (a batch just executed, nothing lettered): the whole line, today.
class Accounting::InvoiceSettlement
  TRADE_ACCOUNTS = Accounting::Actions::PayLetteredInvoices::TRADE_ACCOUNTS

  Item = Struct.new(:value_date, :transaction_date, :reference, :description, :amount, :currency, :amount_eur, :shared, :source,
                    keyword_init: true) do
    def to_payload
      { value_date: value_date.iso8601, transaction_date: transaction_date.iso8601, reference: reference, description: description,
        amount: amount.to_s("F"), currency: currency, amount_eur: amount_eur.to_s("F"), shared: shared, source: source }
    end
  end

  Result = Struct.new(:items, :amount_eur, :paid_on, :reference, keyword_init: true) do
    def to_payload
      { amount_eur: amount_eur.to_s("F"), paid_on: paid_on.iso8601, reference: reference, settlements: items.map(&:to_payload) }
    end
  end

  def self.call(invoice) = new(invoice).call

  def initialize(invoice)
    @invoice = invoice
    @trade   = invoice.journal_entry&.lines&.joins(:account)&.find_by(accounting_accounts: { code: TRADE_ACCOUNTS })
    @seen    = []
  end

  def call
    items = from_payment_lines + from_allocations + from_batches
    items = from_lettering if items.empty?
    items = [ fallback ] if items.empty?
    latest = items.max_by(&:value_date)
    Result.new(items: items, amount_eur: items.sum(&:amount_eur), paid_on: latest.value_date, reference: latest.reference)
  end

  private

  # Payments go against the side opposite to the invoice's own line: a debit for a supplier invoice.
  def payment_side = @trade.credit.positive? ? :debit : :credit

  def from_payment_lines
    return [] unless @trade

    Accounting::JournalEntryLine.where(invoice_id: @invoice.id).where.not(id: @trade.id).where("#{payment_side} > 0")
                                .includes(:journal_entry).map do |line|
      @seen << line.id
      from_entry(line.journal_entry, line.public_send(payment_side))
    end
  end

  def from_allocations
    return [] unless @trade

    Accounting::LineAllocation.touching(@trade.id).includes(debit_line: :journal_entry, credit_line: :journal_entry).filter_map do |allocation|
      other = allocation.debit_line_id == @trade.id ? allocation.credit_line : allocation.debit_line
      next if @seen.include?(other.id)

      @seen << other.id
      from_entry(other.journal_entry, allocation.amount, allocation.allocated_on)
    end
  end

  def from_batches
    Accounting::PaymentBatchLine.active.where(invoice_id: @invoice.id).includes(:payment_batch).filter_map do |line|
      batch = line.payment_batch
      next unless batch.executed?

      build(amount_eur: line.amount, tx: transaction_of(batch.journal_entry_id), reference: batch.message_id, source: "payment_batch",
            date: batch.executed_at&.to_date || batch.requested_execution_date)
    end
  end

  # Payments lettered against the line without any link to this invoice: each counterpart entry, up to what the line owes.
  def from_lettering
    return [] unless @trade&.lettering_id

    remaining = @trade.debit + @trade.credit
    Accounting::JournalEntryLine.where(lettering_id: @trade.lettering_id).where.not(id: @trade.id).where("#{payment_side} > 0")
                                .includes(:journal_entry).order(:id).filter_map do |line|
      amount = [ line.public_send(payment_side), remaining ].min
      next unless amount.positive?

      remaining -= amount
      from_entry(line.journal_entry, amount)
    end
  end

  def fallback
    build(amount_eur: @trade ? @trade.debit + @trade.credit : @invoice.total_incl_vat_eur, tx: nil, reference: nil, source: "transition", date: Date.current)
  end

  def from_entry(entry, amount_eur, date = nil)
    build(amount_eur: amount_eur, tx: transaction_of(entry.id), reference: entry.reference, source: "journal_entry",
          date: date || entry.entry_date, description: entry.description)
  end

  def transaction_of(journal_entry_id)
    Accounting::BankTransaction.find_by(journal_entry_id: journal_entry_id) if journal_entry_id
  end

  def build(amount_eur:, tx:, reference:, source:, date:, description: nil)
    Item.new(
      value_date: tx&.value_date || tx&.transaction_date || date, transaction_date: tx&.transaction_date || date,
      reference: tx&.reference.presence || reference, description: tx&.description.presence || description,
      amount: tx ? tx.amount.abs : amount_eur, currency: tx ? tx.currency : "EUR", amount_eur: amount_eur,
      shared: tx.present? && tx.currency == "EUR" && tx.amount.abs != amount_eur, source: tx ? "bank_transaction" : source
    )
  end
end
