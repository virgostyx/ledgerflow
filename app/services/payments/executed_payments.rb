# "Paiements exécutés" (B01c §6): what was paid, invoice by invoice, with the batch, the payment, the entry and the line of the statement, for the auditor. Only what the bank debited
# (the payments confirmed or returned of a batch debited in the period). The IBAN is masked. => Reports::Result, with the columns for the CSV and XLSX exporters.
class Payments::ExecutedPayments
  Row = Struct.new(:batch_reference, :execution_date, :debit_date, :supplier, :masked_iban, :end_to_end_id, :invoice_number, :amount, :entry_reference, :statement_reference, :status, keyword_init: true)

  COLUMNS = [ [ "Batch", :batch_reference ], [ "Execution date", :execution_date ], [ "Debit date", :debit_date ], [ "Supplier", :supplier ], [ "Account", :masked_iban ],
              [ "End-to-end id", :end_to_end_id ], [ "Invoice", :invoice_number ], [ "Amount", :amount ], [ "Entry", :entry_reference ], [ "Statement reference", :statement_reference ],
              [ "Status", :status ] ].freeze

  def self.call(range)
    links = Payments::ItemInvoice.joins(item: :batch).where(payment_items: { status: %i[confirmed returned] }, payment_batches: { status: %i[debited partially_rejected], debited_at: range.first.beginning_of_day..range.last.end_of_day })
                                 .includes(:invoice, item: [ :partner, :journal_entry, :bank_transaction, { batch: [] } ]).order("payment_batches.debited_at", "payment_items.id", :id)
    rows = links.map { |link| row(link) }
    Reports::Result.new(rows: rows, totals: { amount: rows.sum(&:amount) }, filters: Reports::Filters.new(date_from: range.first, date_to: range.last))
  end

  def self.row(link)
    item = link.item
    batch = item.batch
    Row.new(batch_reference: batch.reference, execution_date: batch.requested_execution_date, debit_date: item.bank_transaction&.transaction_date || batch.debit_date || batch.debited_at.to_date,
            supplier: item.partner.name, masked_iban: item.masked_iban, end_to_end_id: item.end_to_end_id, invoice_number: link.invoice.invoice_number, amount: link.amount,
            entry_reference: item.journal_entry&.reference, statement_reference: item.bank_transaction&.bank_reference || batch.debit_reference, status: item.status)
  end
  private_class_method :row
end
