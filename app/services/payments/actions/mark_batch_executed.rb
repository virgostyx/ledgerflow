class Payments::Actions::MarkBatchExecuted
  extend LightService::Action

  expects :payment_batch, :journal_entry

  executed do |ctx|
    batch = ctx.payment_batch
    batch.update!(executed_at: Time.current, journal_entry: ctx.journal_entry)
    batch.execute!
  rescue StandardError => e
    ctx.fail!("Could not mark payment batch as executed: #{e.message}")
  end
end
