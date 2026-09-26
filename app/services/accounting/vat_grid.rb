module Accounting::VatGrid
  RATE_TO_GRID = {
    sale: { 21 => 3, 12 => 2, 6 => 1, 0 => 0 }
  }.freeze

  VAT_LINE_GRID = { sale: 54, purchase: 59 }.freeze

  # Base amount grids for treatments where no VAT is charged to the partner.
  # Sale side: the partner self-assesses (reverse charge) or nothing is due (export/exempt).
  # Purchase side: only reverse-charge treatments apply — the entity self-assesses.
  TREATMENT_BASE_GRID = {
    sale: {
      intracom_goods:              46,
      intracom_services:           44,
      construction_reverse_charge: 45,
      export:                      47,
      exempt:                      0
    },
    purchase: {
      intracom_goods:              86,
      intracom_services:           88,
      construction_reverse_charge: 87
    }
  }.freeze

  # Grid for the self-assessed "VAT due" line posted on reverse-charge purchases
  # (mirrored by a grid-59 deductible line for the same amount).
  SELF_ASSESSED_VAT_GRID = {
    intracom_goods:              55,
    intracom_services:           55,
    construction_reverse_charge: 56
  }.freeze

  # Credit notes are reported in their own grids, never netted from the grids of the original
  # operation (notice n° 98, 252). Sale base: 48 for grids 44/46, 49 otherwise; sale VAT: 64.
  # Purchase VAT mentioned on a credit note: 63. Reverse-charge purchase credit notes regularize
  # the VAT in 62 (due VAT recovered) and 61 (deduction reversed).
  SALE_CREDIT_VAT_GRID     = 64
  PURCHASE_CREDIT_VAT_GRID = 63
  REVERSE_CHARGE_CREDIT_DUE_GRID        = 62
  REVERSE_CHARGE_CREDIT_DEDUCTIBLE_GRID = 61

  # Balance of the period (notice n° 256-259): XX = tax due (54+55+56+57+61+63), YY = deductible
  # tax (59+62+64). Grid 71 when XX >= YY (0,00 if equal or empty), grid 72 when YY > XX.
  def self.balance(grids)
    sum = ->(codes) { codes.sum { |c| grids[format("%02d", c)].to_d } }
    due, deductible = sum.([ 54, 55, 56, 57, 61, 63 ]), sum.([ 59, 62, 64 ])
    deductible > due ? { "72" => deductible - due } : { "71" => due - deductible }
  end

  def self.sale_credit_grid(treatment)
    %w[intracom_goods intracom_services].include?(treatment.to_s) ? 48 : 49
  end

  # Reverse-charge purchases are also reported in a base grid 81-83 (they add up, they do not replace).
  REVERSE_CHARGE_PURCHASE_GRIDS = [ 86, 87, 88 ].freeze

  # Purchase base grid by the nature of the expense account (notice n° 149-156):
  # 60x goods and materials, 61 and 64 various goods/services, 20-27 investments.
  def self.purchase_base_grid(account_code)
    case account_code.to_s
    when /\A60/ then 81
    when /\A(61|64)/ then 82
    when /\A2[0-7]/ then 83
    end
  end

  LABELS = {
    0  => "Exempt/exported sales",
    61 => "VAT prorata regularization (owed to the State)",
    62 => "VAT prorata regularization (recovered)",
    1  => "Sales at 6%",
    2  => "Sales at 12%",
    3  => "Sales at 21%",
    44 => "Intracommunity services supplied (B2B)",
    45 => "Reverse-charge sales (VAT due by the customer)",
    46 => "Intracommunity supplies of goods",
    47 => "Exported and other exempt sales",
    48 => "Credit notes issued on intracommunity sales",
    49 => "Credit notes issued on other sales",
    54 => "VAT due on sales",
    55 => "VAT due on intracommunity acquisitions and services",
    56 => "VAT due on other reverse-charge purchases",
    59 => "Deductible VAT",
    63 => "VAT to reverse on credit notes received",
    64 => "VAT to recover on credit notes issued",
    81 => "Purchases of goods and materials",
    82 => "Purchases of various goods and services",
    83 => "Purchases of investment goods",
    86 => "Intracommunity acquisitions of goods",
    87 => "Other reverse-charge purchases",
    84 => "Credit notes received on intracommunity acquisitions",
    85 => "Credit notes received on other purchases",
    88 => "Intracommunity services received"
  }.freeze

  def self.label(code)
    LABELS[code.to_i] || code.to_s
  end
end
