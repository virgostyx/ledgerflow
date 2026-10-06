# The envelope every tool answers in (A02 §5): the rows, the totals, the currency, the date it stands at, the filters really applied, how many rows came back,
# whether the answer is partial, and the warnings of the report. Amounts are decimal strings with two decimals, never numbers: the model copies them, it does not compute.
module Agent::ToolResult
  MAX_BYTES = 20_000
  CUT_WARNING = "The result was cut to fit: narrow the filters (period, partner, account) to see the rest.".freeze

  def self.build(data:, totals: nil, currency: nil, as_of: nil, filters_applied: {}, truncated: false, warnings: [])
    kept = fit(data, totals, currency, as_of, filters_applied, warnings)
    cut = truncated || kept.size < data.size
    envelope(kept, totals, currency, as_of, filters_applied, cut, cut && kept.size < data.size ? warnings + [ CUT_WARNING ] : warnings)
  end

  # "1234.50" for what a person would write 1 234,50. A Float is refused: it would carry a rounding error into a ledger.
  def self.money(amount)
    raise ArgumentError, "an amount is never a Float (got #{amount.inspect})" if amount.is_a?(Float)

    whole, fraction = BigDecimal((amount.nil? ? 0 : amount).to_s).round(2).to_s("F").split(".")
    "#{whole}.#{fraction.to_s.ljust(2, '0')}"
  end

  def self.envelope(data, totals, currency, as_of, filters, truncated, warnings)
    { "data" => data, "totals" => totals, "currency" => currency, "as_of" => as_of&.to_s, "filters_applied" => filters,
      "row_count" => data.size, "truncated" => truncated, "warnings" => warnings }.compact
  end
  private_class_method :envelope

  # The longest run of rows, from the first, that keeps the whole answer under the limit (a binary search: the size grows with the number of rows).
  def self.fit(data, totals, currency, as_of, filters, warnings)
    too_big = ->(rows) { envelope(rows, totals, currency, as_of, filters, true, warnings + [ CUT_WARNING ]).to_json.bytesize > MAX_BYTES }
    return data unless too_big.call(data)

    low, high = 0, data.size - 1
    while low < high
      middle = (low + high + 1) / 2
      too_big.call(data.first(middle)) ? high = middle - 1 : low = middle
    end
    data.first(low)
  end
  private_class_method :fit
end
