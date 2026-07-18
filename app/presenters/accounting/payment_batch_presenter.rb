class Accounting::PaymentBatchPresenter
  def initialize(payment_batch)
    @payment_batch = payment_batch
  end

  def formatted_total
    Accounting::MoneyPresenter.new(@payment_batch.total_amount).format
  end

  def formatted_requested_execution_date
    Accounting::DatePresenter.new(@payment_batch.requested_execution_date).format
  end

  def status_label
    Accounting::StatusPresenter.new(@payment_batch.status).label
  end

  def status_badge_variant
    Accounting::StatusPresenter.new(@payment_batch.status).badge_variant
  end

  def line_count
    @payment_batch.lines.count
  end
end
