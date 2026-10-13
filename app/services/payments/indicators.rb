# What the payments say about how the company pays (B01c §6 "Indicateurs"), over a period of debits: how many batches were debited, how many were recognised from the statement (the
# others were confirmed by hand), the mean delay between the due date and the debit, the payments made after their due date, and what came back. Added up by the database.
# `mean_days_late` is negative for what was paid early.
class Payments::Indicators
  Result = Struct.new(:batches, :recognised_from_statement, :recognition_rate, :mean_days_late, :late_payments, :late_amount, :returned_amount, keyword_init: true)

  def self.call(range) = new(range).call

  def initialize(range)
    @range = range
  end

  def call
    batches = Payments::Batch.where(status: %i[debited partially_rejected], debited_at: @range.first.beginning_of_day..@range.last.end_of_day)
    statement = batches.where(debit_kind: "statement").count
    total = batches.count
    mean, late_count, late_amount = lateness(batches)
    Result.new(batches: total, recognised_from_statement: statement, recognition_rate: (BigDecimal(statement) / total if total.positive?), mean_days_late: mean,
               late_payments: late_count, late_amount: late_amount, returned_amount: returned(batches))
  end

  private

  DEBIT_DAY = "COALESCE(bt.transaction_date, b.debit_date, b.debited_at::date)".freeze

  # [mean days late, number of payments paid after their due date, their amount]
  def lateness(batches)
    row = base(batches).where.not(invoices: { due_date: nil })
                       .pick(Arel.sql("AVG(#{DEBIT_DAY} - invoices.due_date)"), Arel.sql("COUNT(*) FILTER (WHERE #{DEBIT_DAY} > invoices.due_date)"),
                             Arel.sql("COALESCE(SUM(payment_item_invoices.amount) FILTER (WHERE #{DEBIT_DAY} > invoices.due_date), 0)"))
    mean, count, amount = row
    [ (BigDecimal(mean.to_s) if mean), count.to_i, BigDecimal(amount.to_s) ]
  end

  def returned(batches) = Payments::Item.where(status: :returned, batch_id: batches.select(:id)).sum(:amount)

  # Each payment of a debited batch, with its invoice and the line that debited it.
  def base(batches)
    Payments::ItemInvoice.joins(:item).joins("JOIN payment_batches b ON b.id = payment_items.batch_id")
                         .joins("JOIN accounting_invoices invoices ON invoices.id = payment_item_invoices.invoice_id")
                         .joins("LEFT JOIN accounting_bank_transactions bt ON bt.id = payment_items.bank_transaction_id")
                         .where(payment_items: { status: %i[confirmed returned] }).where("b.id IN (?)", batches.select(:id))
  end
end
