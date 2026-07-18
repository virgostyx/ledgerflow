class Payments::Actions::MarkInvoicesPaid
  extend LightService::Action

  expects :payment_batch

  executed do |ctx|
    ctx.payment_batch.lines.includes(:invoice).each { |line| line.invoice.pay! }
  rescue AASM::InvalidTransition, ActiveRecord::RecordInvalid => e
    ctx.fail!("Could not mark invoice as paid: #{e.message}")
  end
end
