module Accounting::VatGrid
  RATE_TO_GRID = {
    sale:     { 21 => 1, 12 => 2, 6 => 3, 0 => 0 },
    purchase: { 21 => 81, 12 => 82, 6 => 83 }
  }.freeze

  VAT_LINE_GRID = { sale: 54, purchase: 59 }.freeze

  # Base amount grids for treatments where no VAT is charged to the partner.
  # Sale side: the partner self-assesses (reverse charge) or nothing is due (export/exempt).
  # Purchase side: only reverse-charge treatments apply — the entity self-assesses.
  TREATMENT_BASE_GRID = {
    sale: {
      intracom_goods:              46,
      intracom_services:           47,
      construction_reverse_charge: 48,
      export:                      49,
      exempt:                      0
    },
    purchase: {
      intracom_goods:              86,
      intracom_services:           87,
      construction_reverse_charge: 88
    }
  }.freeze

  # Grid for the self-assessed "VAT due" line posted on reverse-charge purchases
  # (mirrored by a grid-59 deductible line for the same amount).
  SELF_ASSESSED_VAT_GRID = {
    intracom_goods:              56,
    intracom_services:           56,
    construction_reverse_charge: 57
  }.freeze

  LABELS = {
    0  => "Exempt/exported sales",
    1  => "Sales at 21%",
    2  => "Sales at 12%",
    3  => "Sales at 6%",
    46 => "Intracommunity supplies of goods",
    47 => "Intracommunity supplies of services",
    48 => "Reverse-charge construction sales",
    49 => "Exported sales",
    54 => "VAT due on sales",
    56 => "VAT due on intracommunity acquisitions",
    57 => "VAT due on other reverse-charge purchases",
    59 => "Deductible VAT",
    81 => "Purchases at 21%",
    82 => "Purchases at 12%",
    83 => "Purchases at 6%",
    86 => "Intracommunity acquisitions of goods",
    87 => "Services received under reverse charge",
    88 => "Reverse-charge construction purchases"
  }.freeze

  def self.label(code)
    LABELS[code.to_i] || code.to_s
  end
end
