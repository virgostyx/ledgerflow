# F12b step 3, translation of a member that keeps its accounts in another currency (F11): the balance sheet at the closing rate, the income statement at the
# average rate, and the difference between the two placed in the heading of equity the validated rule names, so that the translated statements balance. It runs in
# the tenant of the member, which holds its own rates, and only with the parameters of an accountant's validation: no rate is ever replaced by another.
# The average rate is the mean of the monthly average rates (F11) of the months of the fiscal year up to the reporting date; a month without one is an error.
module Consolidation::Translate
  class Failed < StandardError; end

  RATE_TYPES = { "balance_rate_type" => %w[closing], "income_rate_type" => %w[monthly_average closing] }.freeze

  # => the member data with its `own` figures in the currency of the group, and `translation` saying how
  def self.call(member, parameters:, group_currency:, date:)
    raise Failed, "the group currency must be EUR for now (the rates of F11 are units of currency for 1 EUR)" if group_currency != "EUR"

    RATE_TYPES.each { |key, allowed| raise Failed, "#{key} #{parameters[key].inspect} is not supported (#{allowed.join(', ')})" unless allowed.include?(parameters[key]) }
    entity = Entity.find(member["entity_id"])
    closing, average = ActsAsTenant.with_tenant(entity) { [ closing_rate(member["currency"], date), average_rate(member["currency"], Date.parse(member["fy_start"]), date, parameters["income_rate_type"]) ] }
    own = member["own"].to_h { |code, amount| [ code, BigDecimal(amount) ] }
    translated = own.to_h do |code, amount|
      statement = Consolidation::Statements::STATEMENTS.find { |s| Consolidation::Statements.leaf(s, code) }
      [ code, (amount / (statement == "income" ? average : closing)).round(2) ]
    end
    figures = Consolidation::Statements.compute(own: translated)
    difference = Consolidation::Statements.difference(figures)
    heading = parameters["difference_heading"]
    raise Failed, "#{heading} is not a heading of the liabilities that holds accounts" unless Consolidation::Statements.leaf("liabilities", heading)

    translated[heading] = translated.fetch(heading, BigDecimal("0")) + difference
    balanced = Consolidation::Statements.compute(own: translated)
    member.merge("own" => translated.transform_values { |v| v.to_s("F") }, "figures" => balanced.transform_values { |v| v.to_s("F") }, "translated" => true,
                 "translation" => { "closing_rate" => closing.to_s("F"), "average_rate" => average.to_s("F"), "difference" => difference.to_s("F"), "difference_heading" => heading })
  end

  def self.closing_rate(currency, date) = Fx::RateFor.closing(currency, date)

  def self.average_rate(currency, from, to, type)
    return closing_rate(currency, to) if type == "closing"

    months = (from..to).map(&:beginning_of_month).uniq
    rates = months.map do |month|
      Accounting::ExchangeRate.monthly_average.where(currency: currency, rate_date: month).order(:id).last&.rate || raise(Fx::MissingRate.new(currency, month, kind: "monthly average"))
    end
    rates.sum(BigDecimal("0")) / rates.size
  end
  private_class_method :closing_rate, :average_rate
end
