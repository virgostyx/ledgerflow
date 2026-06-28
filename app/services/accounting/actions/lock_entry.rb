class Accounting::Actions::LockEntry
  extend LightService::Action

  expects :entry

  executed do |ctx|
    ctx.entry.with_lock do
      ctx.entry.reload
      ctx.fail_with_rollback!("Entry is already posted.") unless ctx.entry.draft?
      ctx.entry.locked_by = "system"
      ctx.entry.locked_at = Time.current
      ctx.entry.post!
    end
  end
end
