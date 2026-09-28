# Default cash-flow category per PCMN code family (docs/dev/reports/spec.md §12, R15). An account's
# own `cash_flow_category` overrides it; a family with no default stays unclassified ("Non classé").
module Accounting::CashFlowCategories
  CATEGORIES = %w[operating investing financing transfer].freeze

  INVESTING_PREFIXES = %w[20 21 22 23 24 25 26 27 28 50 51 52 53 54].freeze
  FINANCING_PREFIXES = %w[10 11 12 13 14 15 17 42 43 47].freeze
  TRANSFER_PREFIXES  = %w[58].freeze
  OPERATING_PREFIXES = %w[16 29 3 40 41 44 45 46 48 49 6 7].freeze
  CASH_PREFIXES      = %w[55 57].freeze

  module_function

  def default_for(code)
    return "investing" if starts_with?(code, INVESTING_PREFIXES)
    return "financing" if starts_with?(code, FINANCING_PREFIXES)
    return "transfer"  if starts_with?(code, TRANSFER_PREFIXES)

    "operating" if starts_with?(code, OPERATING_PREFIXES)
  end

  def cash?(code) = starts_with?(code, CASH_PREFIXES)

  def starts_with?(code, prefixes) = prefixes.any? { |p| code.to_s.start_with?(p) }
end
