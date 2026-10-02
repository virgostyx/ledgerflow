# F01: nothing is posted with an entry date inside a locked period.
class Accounting::Actions::ValidatePeriodOpen
  extend LightService::Action

  expects :entry

  executed do |ctx|
    lock = Accounting::PeriodLock.covering(ctx.entry.entry_date).first
    if lock
      ctx.fail_with_rollback!(I18n.t("accounting.errors.period_locked", starts_on: lock.starts_on, ends_on: lock.ends_on))
    end
  end
end
