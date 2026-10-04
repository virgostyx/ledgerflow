# The rules of an entry with lines in a foreign currency (F11), before it is validated. Each foreign line carries its amount in the currency
# (signed like the line, with the decimals of that currency), a positive rate (units of currency for 1 EUR) that agrees with the euros to the cent
# (a bank gives the euros and the rate is derived, so one cent of slack), and a document wholly in one currency balances in that currency too.
# Converting line by line leaves up to 2 cents: they go to a line of their own on the exchange difference account of the right side, labelled as
# the rounding of the conversion; anything more is a real imbalance and is left for ValidateBalance to refuse.
class Accounting::Actions::ApplyForeignCurrency
  extend LightService::Action

  expects :entry

  MAX_ROUNDING = BigDecimal("0.02")

  executed do |ctx|
    lines   = ctx.entry.lines.reload.to_a
    foreign = lines.reject { |l| l.currency == "EUR" }
    next if foreign.empty?

    error = foreign.filter_map { |line| line_error(line) }.first || currency_balance_error(lines, foreign)
    error ||= add_rounding_line(ctx.entry, lines)
    ctx.fail_with_rollback!(error) if error
  end

  def self.line_error(line)
    code = line.currency
    return "A line on #{line.account.code} is in #{code} but has no amount in #{code}." if line.amount_currency.nil? || line.amount_currency.zero?
    return "The #{code} rate of a line on #{line.account.code} must be positive." unless line.exchange_rate&.positive?
    return "The sign of the #{code} amount of a line on #{line.account.code} must follow its side: positive on a debit, negative on a credit." unless line.amount_currency.positive? == line.debit.positive?

    decimals = Accounting::Currency.decimals_of(code)
    return "#{code} amounts have #{decimals} decimals: #{line.amount_currency.to_s('F')} is not valid." unless line.amount_currency == line.amount_currency.round(decimals)

    euros = line.debit + line.credit
    expected = Fx::Convert.to_eur(line.amount_currency.abs, line.exchange_rate)
    "#{line.amount_currency.abs.to_s('F')} #{code} at #{line.exchange_rate.to_s('F')} is #{expected.to_s('F')} EUR, not #{euros.to_s('F')}." if (euros - expected).abs > BigDecimal("0.01")
  end
  private_class_method :line_error

  def self.currency_balance_error(lines, foreign)
    return unless lines.size == foreign.size && foreign.map(&:currency).uniq.one?

    total = foreign.sum(&:amount_currency)
    "The entry does not balance in #{foreign.first.currency}: #{total.to_s('F')} left." unless total.zero?
  end
  private_class_method :currency_balance_error

  def self.add_rounding_line(entry, lines)
    diff = lines.sum(&:debit) - lines.sum(&:credit)
    return if diff.round(2).zero? || diff.abs > MAX_ROUNDING

    entity = entry.entity
    code = diff.positive? ? entity.fx_gain_account_code : entity.fx_loss_account_code
    account = Accounting::Account.find_by(code: code)
    return "The exchange difference account #{code} does not exist: create it (Settings > Chart of accounts) to post an entry in a foreign currency." unless account

    Accounting::JournalEntryLine.create!(journal_entry: entry, account: account, label: "Conversion rounding", currency: "EUR",
                                         debit: diff.negative? ? diff.abs : 0, credit: diff.positive? ? diff : 0, sort_order: lines.map(&:sort_order).max.to_i + 1)
    nil
  end
  private_class_method :add_rounding_line
end
