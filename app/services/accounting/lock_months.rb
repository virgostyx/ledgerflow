# Locks several whole months in one go (the grouped action of the Periods screen): one lock, one audit entry per month.
# A month already locked for that kind is skipped. months: ["2026-01", ...] => ctx[:locked] (how many), ctx.fail! if none.
class Accounting::LockMonths
  def self.call(months:, user:, kind: :accounting, reason: nil)
    ctx = LightService::Context.make(locked: 0)
    firsts = Array(months).filter_map { |month| parse(month) }.uniq
    return ctx.tap { |c| c.fail!(I18n.t("accounting.period_locks.no_month")) } if firsts.empty? || firsts.size != Array(months).uniq.size

    ApplicationRecord.transaction do
      Accounting::PeriodLock.serialize_for_entity!
      firsts.each do |first|
        next if Accounting::PeriodLock.in_force.where(kind: kind).where("starts_on <= ? AND ends_on >= ?", first, first.end_of_month).exists?

        result = Accounting::LockPeriod.call(starts_on: first, ends_on: first.end_of_month, kind: kind, reason: reason, user: user)
        if result.failure?
          ctx.fail!(result.message)
          raise ActiveRecord::Rollback
        end

        ctx[:locked] += 1
      end
    end
    ctx
  end

  def self.parse(month)
    Date.strptime(month.to_s, "%Y-%m") if month.to_s.match?(/\A\d{4}-\d{2}\z/)
  rescue Date::Error
    nil
  end
  private_class_method :parse
end
