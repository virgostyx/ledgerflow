class Accounting::Actions::ValidateLettering
  extend LightService::Action

  expects :lines

  executed do |ctx|
    lines = ctx.lines
    error = if lines.size < 2                                              then "Select at least two lines"
    elsif lines.any? { |l| !l.journal_entry.posted? }                      then "Only lines of posted entries can be lettered"
    elsif lines.any?(&:lettering_id)                                       then "A line is already lettered"
    elsif lines.map(&:account_id).uniq.size > 1                            then "Lines must be on the same account"
    elsif lines.map(&:partner_id).uniq.size > 1                            then "Lines must have the same partner"
    elsif lines.sum(&:debit) != lines.sum(&:credit)                        then "Debits and credits must balance"
    end
    ctx.fail!(error) if error
  end
end
