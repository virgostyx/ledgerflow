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
    elsif (problem = balance_problem(lines))                               then problem
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

  # Lines in EUR cancel out in EUR. Lines in a foreign currency cancel out in that currency (F11): the difference in EUR is the exchange difference
  # that Actions::PostFxAdjustment books. Two currencies, or a currency and EUR, are never lettered together: a conversion entry comes first.
  def self.balance_problem(lines)
    own = lines.reject { |l| l.journal_entry.fx_adjustment? }
    currencies = own.map(&:currency).uniq
    if currencies.size > 1
      foreign = currencies - [ "EUR" ]
      return "Lines in different currencies (#{foreign.to_sentence(two_words_connector: ' and ')}) cannot be lettered together." if foreign.size > 1

      return "A line in #{foreign.first} cannot be lettered with a line in EUR: book a conversion entry first."
    end
    return (lines.sum(&:debit) == lines.sum(&:credit) ? nil : "Debits and credits must balance") if currencies == [ "EUR" ] || currencies.empty?

    left = own.sum { |l| l.amount_currency.to_d }
    "Debits and credits must balance in #{currencies.first} (#{left.to_s('F')} #{currencies.first} left)." unless left.zero?
  end

  def self.split_allocation_group?(lines)
    ids = lines.map(&:id)
    Accounting::LineAllocation.touching(ids).any? { |a| !(ids.include?(a.debit_line_id) && ids.include?(a.credit_line_id)) }
  end
end
