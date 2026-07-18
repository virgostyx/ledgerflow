class Payments::Actions::CreatePaymentBatchRecord
  extend LightService::Action

  expects :invoices, :bank_account, :requested_execution_date
  promises :payment_batch

  executed do |ctx|
    batch = Accounting::PaymentBatch.new(
      bank_account: ctx.bank_account,
      requested_execution_date: ctx.requested_execution_date
    )

    ctx.invoices.each do |invoice|
      batch.lines.build(
        invoice: invoice,
        amount: invoice.total_incl_vat,
        remittance_information: remittance_information_for(invoice)
      )
    end

    batch.save!
    ctx.payment_batch = batch
  rescue StandardError => e
    ctx.fail!("Payment batch creation error: #{e.message}")
  end

  def self.remittance_information_for(invoice)
    return invoice.external_ref if invoice.external_ref.present?
    "#{invoice.invoice_number} - #{invoice.partner.name}".truncate(140)
  end
end
