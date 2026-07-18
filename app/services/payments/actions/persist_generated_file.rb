class Payments::Actions::PersistGeneratedFile
  extend LightService::Action

  expects :payment_batch, :sepa_xml, :message_id

  executed do |ctx|
    batch = ctx.payment_batch
    batch.update!(
      sepa_xml: ctx.sepa_xml,
      message_id: ctx.message_id,
      total_amount: batch.lines.sum(:amount),
      generated_at: Time.current
    )
    batch.generate!
  rescue StandardError => e
    ctx.fail!("Payment batch persistence error: #{e.message}")
  end
end
