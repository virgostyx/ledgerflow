# Stores the quotes a source gave, for the current entity (F11), once each: a quote is a rate of a kind and a source on a date, so the same one again
# changes nothing, and a corrected one replaces the old. A rate that is not positive never gets in (named in `rejected`); a currency the application
# does not know, and EUR, are `ignored`. => Result(created, updated, unchanged, ignored, rejected [[quote, why]])
class Rates::Import
  Result = Struct.new(:created, :updated, :unchanged, :ignored, :rejected)

  def self.call(quotes:, user: nil)
    result = Result.new(0, 0, 0, 0, [])
    supported = Accounting::MoneyPresenter::SUPPORTED_CURRENCIES - [ "EUR" ]
    quotes.each do |quote|
      next result.ignored += 1 unless supported.include?(quote.currency)
      next result.rejected << [ quote, "The rate of #{quote.currency} must be positive (got #{quote.rate.to_s('F')})" ] unless quote.rate.positive?

      store(quote, user, result)
    end
    result
  end

  def self.store(quote, user, result)
    record = Accounting::ExchangeRate.find_or_initialize_by(currency: quote.currency, rate_date: quote.date, rate_type: quote.type, source: quote.source)
    return result.unchanged += 1 if record.persisted? && record.rate == quote.rate

    record.new_record? ? result.created += 1 : result.updated += 1
    record.update!(rate: quote.rate, imported_at: Time.current, created_by: user, reason: (record.reason || "Imported from #{quote.source}" if quote.type == :manual))
  end
  private_class_method :store
end
