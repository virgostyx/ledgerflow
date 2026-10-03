# An owner closes the controlled window before it expires (F01).
class Accounting::CloseControlledWindow
  def self.call(window:, user:)
    ctx = LightService::Context.make(window: window)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.controlled_window.owner_only")) } unless Accounting::PeriodLockPolicy.new(user, Accounting::PeriodLock).unlock?

    ApplicationRecord.transaction do
      window.update!(closed_at: Time.current, closed_by: user)
      Accounting::AuditLog.record!(auditable: window, action: "controlled_window_closed", user: user, payload: { purpose: window.purpose, window_id: window.id })
    end
    ctx
  end
end
