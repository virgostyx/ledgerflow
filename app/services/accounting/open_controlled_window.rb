# An owner opens the window that lets migration or closing write into locked periods (F01). Reason mandatory, 1 to 8
# hours, one at a time, audited. => ctx[:window]
class Accounting::OpenControlledWindow
  def self.call(user:, reason:, purpose:, hours:)
    ctx = LightService::Context.make(window: nil)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.controlled_window.owner_only")) } unless Accounting::PeriodLockPolicy.new(user, Accounting::PeriodLock).unlock?
    return ctx.tap { |c| c.fail!(I18n.t("accounting.controlled_window.reason_required")) } if reason.blank?
    return ctx.tap { |c| c.fail!(I18n.t("accounting.controlled_window.bad_purpose")) } unless Accounting::ControlledWindow::PURPOSES.include?(purpose.to_s)
    unless hours.to_i.between?(1, Accounting::ControlledWindow::MAX_HOURS)
      return ctx.tap { |c| c.fail!(I18n.t("accounting.controlled_window.bad_hours", max: Accounting::ControlledWindow::MAX_HOURS)) }
    end
    return ctx.tap { |c| c.fail!(I18n.t("accounting.controlled_window.already_open")) } if Accounting::ControlledWindow.open_now.exists?

    ApplicationRecord.transaction do
      window = Accounting::ControlledWindow.create!(opened_by: user, purpose: purpose, reason: reason, opens_at: Time.current, expires_at: hours.to_i.hours.from_now)
      Accounting::AuditLog.record!(auditable: window, action: "controlled_window_opened", user: user, reason: reason,
                                   payload: { purpose: purpose, reason: reason, expires_at: window.expires_at.utc.iso8601 })
      ctx[:window] = window
    end
    ctx
  end
end
