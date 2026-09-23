module Accounting::VatGrid
  RATE_TO_GRID = {
    sale:     { 21 => 1, 12 => 2, 6 => 3, 0 => 0 },
    purchase: { 21 => 81, 12 => 82, 6 => 83 }
  }.freeze

  VAT_LINE_GRID = { sale: 54, purchase: 59 }.freeze

  LABELS = {
    0  => "Exempt/exported sales",
    1  => "Sales at 21%",
    2  => "Sales at 12%",
    3  => "Sales at 6%",
    54 => "VAT due on sales",
    59 => "Deductible VAT",
    81 => "Purchases at 21%",
    82 => "Purchases at 12%",
    83 => "Purchases at 6%"
  }.freeze

  def self.label(code)
    LABELS[code.to_i] || code.to_s
  end
end
