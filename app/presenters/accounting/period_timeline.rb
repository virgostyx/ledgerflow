# The months of a fiscal year with a padlock each, per kind of lock (F01 screen "Periods").
# A month is :locked when one lock in force covers all of it, :partial when one covers part of it, :open otherwise.
class Accounting::PeriodTimeline
  attr_reader :fiscal_year

  def initialize(fiscal_year)
    @fiscal_year = fiscal_year
    @locks = Accounting::PeriodLock.in_force
                                   .where("starts_on <= ? AND ends_on >= ?", fiscal_year.end_date, fiscal_year.start_date)
                                   .group_by(&:kind)
  end

  # First day of each month the year touches (a broken year may not start on the 1st).
  def months
    (fiscal_year.start_date.beginning_of_month..fiscal_year.end_date).select { |day| day.day == 1 }
  end

  def state(kind, month)
    from = [ month, fiscal_year.start_date ].max
    to   = [ month.end_of_month, fiscal_year.end_date ].min
    state_between(kind.to_s, from, to)
  end

  def fiscal_year_state = state_between("fiscal_year", fiscal_year.start_date, fiscal_year.end_date)

  private

  def state_between(kind, from, to)
    locks = @locks.fetch(kind, [])
    return :locked if locks.any? { |lock| lock.starts_on <= from && lock.ends_on >= to }

    locks.any? { |lock| lock.starts_on <= to && lock.ends_on >= from } ? :partial : :open
  end
end
