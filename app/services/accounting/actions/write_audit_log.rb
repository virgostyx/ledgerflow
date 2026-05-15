class Accounting::Actions::WriteAuditLog
  extend LightService::Action

  expects :entry

  executed do |ctx|
    Accounting::AuditLog.record!(
      auditable: ctx.entry,
      action:    "post_entry",
      payload:   { reference: ctx.entry.reference }
    )
  end
end
