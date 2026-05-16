class Accounting::Actions::MarkTransactionReconciled
  extend LightService::Action

  expects :transaction, :journal_entry

  executed do |ctx|
    ctx.transaction.update!(
      status:        :reconciled,
      journal_entry: ctx.journal_entry
    )
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!(e.record.errors.full_messages.join(", "))
  end
end
