class Accounting::Actions::ValidateLettering
  extend LightService::Action

  expects :lines

  executed do |ctx|
    lines = ctx.lines
    error = if lines.size < 2                                              then "Select at least two lines"
    elsif lines.any? { |l| !l.journal_entry.in_ledger? }                   then "Only lines of posted entries can be lettered"
    elsif lines.any?(&:lettering_id)                                       then "A line is already lettered"
    elsif lines.map(&:account_id).uniq.size > 1                            then "Lines must be on the same account"
    elsif (problem = partner_problem(ctx, lines))                          then problem
    elsif split_allocation_group?(lines)                                   then "A partly settled line can only be lettered with its whole allocation group"
    elsif lines.sum(&:debit) != lines.sum(&:credit)                        then "Debits and credits must balance"
    end
    ctx.fail!(error) if error
  end

  # Lines of different partners: a correction, which needs the right, and says why.
  def self.partner_problem(ctx, lines)
    return unless lines.map(&:partner_id).uniq.size > 1
    return "Lines must have the same partner" unless ctx[:cross_partner]
    return "Say why lines of different partners are lettered together" if ctx[:reason].blank?
    return if ctx[:user] && Accounting::LetteringPolicy.new(ctx[:user], :lettering).cross_partner?

    "You are not allowed to letter lines of different partners"
  end

  def self.split_allocation_group?(lines)
    ids = lines.map(&:id)
    Accounting::LineAllocation.touching(ids).any? { |a| !(ids.include?(a.debit_line_id) && ids.include?(a.credit_line_id)) }
  end
end
