# Who is proposed for a reminder at `as_of` (F09), worked out from the open customer lines (R05, so the amounts of R04): one row per customer, the
# customer that is the latest to pay first. A line is asked for when it is overdue by the first level's delay, is neither disputed nor under a
# promise of payment that has not passed, was not reminded in the last `min_days_between` days, and has reached the delay of the level after the last one sent. A customer is proposed when what is
# asked for reaches the policy's minimum, and is not marked "do not remind". The row's `level` is never more than one above the last level sent
# on any of its lines (`delay_level` is what the delay alone would say): going higher is a choice that needs confirming.
# `statement` is every open line of the customer, due or not, so that the balance is R04's; credits not yet allocated are shown, never deducted.
class Accounting::DunningCandidates
  Row = Struct.new(:partner, :lines, :statement, :credits, :total, :balance, :oldest_days, :level, :delay_level, :channel, :recipient, keyword_init: true)

  def self.call(**) = new(**).call

  def initialize(as_of: Date.current, policy: nil)
    @as_of  = as_of
    @policy = policy || Accounting::DunningPolicy.for(ActsAsTenant.current_tenant)
  end

  def call
    open_rows = Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: @as_of).call.select(&:partner_id)
    flags     = Accounting::JournalEntryLine.where(id: open_rows.map(&:line_id)).index_by(&:id)
    partners  = Accounting::Partner.where(id: open_rows.map(&:partner_id).uniq, do_not_dun: false).index_by(&:id)

    open_rows.group_by(&:partner_id).filter_map { |id, rows| row(partners[id], rows, flags) }.sort_by { |r| -r.oldest_days }
  end

  private

  def row(partner, rows, flags)
    return unless partner

    due = rows.select { |r| r.residual.positive? && asked_for?(r, flags.fetch(r.line_id)) }
    return if due.empty? || due.sum(&:residual) < @policy.min_amount

    delay_level = @policy.level_for_delay(due.map(&:age_days).max)
    level = due.map { |r| [ @policy.level_for_delay(r.age_days), flags.fetch(r.line_id).dunning_level + 1 ].min }.max
    Row.new(partner: partner, lines: due, statement: rows, credits: rows.select { |r| r.residual.negative? },
            total: due.sum(&:residual), balance: rows.sum(&:residual), oldest_days: due.map(&:age_days).max,
            level: level, delay_level: delay_level, channel: partner.email.present? ? "email" : "letter", recipient: partner.email.presence)
  end

  def asked_for?(row, line)
    return false if line.disputed || (line.payment_promised_on && line.payment_promised_on >= @as_of)

    return false if line.last_dunned_at && line.last_dunned_at.to_date + @policy.min_days_between > @as_of

    next_level = line.dunning_level + 1
    next_level <= Accounting::DunningPolicy::LEVELS.last && @policy.level_for_delay(row.age_days) >= next_level
  end
end
