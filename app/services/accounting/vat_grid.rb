# Every grid decision for invoice postings and the VAT return, read from the data seeded by
# Seeders::VatCodesSeeder (accounting_vat_codes / _grid_mappings / _account_grid_rules,
# docs/dev/reports/spec.md §10) — not hardcoded. Cached per process, reset when any of those
# rows is saved (or via .reset!). Raises NotSeeded rather than silently posting no grids.
module Accounting::VatGrid
  class NotSeeded < StandardError; end

  Snapshot = Struct.new(:mappings, :account_rules, keyword_init: true)

  # Balance of the period (notice n° 256-259): XX = tax due (54+55+56+57+61+63), YY = deductible
  # tax (59+62+64). Grid 71 when XX >= YY (0,00 if equal or empty), grid 72 when YY > XX.
  def self.balance(grids)
    sum = ->(codes) { codes.sum { |c| grids[format("%02d", c)].to_d } }
    due, deductible = sum.([ 54, 55, 56, 57, 61, 63 ]), sum.([ 59, 62, 64 ])
    deductible > due ? { "72" => deductible - due } : { "71" => due - deductible }
  end

  def self.reset! = (@snapshot = nil)

  # The mapping for a nature and document type, or nil when that combination has no code (e.g. a
  # purchase with an export treatment). `rate` picks the code of a domestic sale (its base grid
  # depends on it); without one, any domestic code answers — credit-note mappings and due grids
  # don't depend on the rate.
  def self.mapping(sens, nature, document_type = :invoice, rate: nil)
    candidates = snapshot.mappings.select do |m|
      c = m.vat_code
      c.sens == sens.to_s && c.nature == nature.to_s && m.document_type == document_type.to_s
    end
    return candidates.first unless sens.to_s == "sale" && nature.to_s == "domestic"
    return candidates.find { |m| m.vat_code.rate.to_i == rate.to_i } if rate

    candidates.max_by { |m| m.vat_code.rate.to_i }
  end

  # Purchase base grid by the nature of the expense account (notice n° 149-156).
  def self.purchase_base_grid(account_code)
    rule = snapshot.account_rules.select { |r| account_code.to_s.start_with?(r.account_prefix) }
                   .max_by { |r| r.account_prefix.length }
    rule&.base_grid
  end

  # Grid of VAT deductible on domestic purchases (59), and of VAT mentioned on a purchase credit note (63).
  def self.purchase_deductible_vat_grid(document_type = :invoice)
    mapping(:purchase, :domestic, document_type).deductible_vat_grid
  end

  def self.sale_due_vat_grid(document_type = :invoice)
    snapshot.mappings.select { |m| m.vat_code.sale? && m.vat_code.domestic? && m.document_type == document_type.to_s }
            .filter_map(&:due_vat_grid).first
  end

  # Credit-note base grid of a sale: 48 for grids 44/46, 49 otherwise.
  def self.sale_credit_grid(treatment) = mapping(:sale, treatment, :credit_note)&.base_grid

  # Base grids a sale invoice can land in (rate-driven and treatment-driven), and the exempt one.
  def self.sale_base_grids
    snapshot.mappings.select { |m| m.vat_code.sale? && m.invoice? }.filter_map(&:base_grid).uniq
  end

  def self.exempt_sale_grid = mapping(:sale, :exempt)&.base_grid

  # Reverse-charge purchases (86-88) are also reported in a base grid 81-83 (they add up, they do not replace).
  def self.reverse_charge_purchase_grids
    snapshot.mappings.select { |m| m.vat_code.purchase? && !m.vat_code.domestic? && m.invoice? }.filter_map(&:base_grid).uniq
  end

  # { recap grid => [base grids whose credit-note amounts it recaps] }, e.g. 84 => [86, 88].
  def self.credit_note_recap_grids
    pairs = snapshot.mappings.select { |m| m.vat_code.purchase? && m.credit_note? && m.credit_note_recap_grid }
                    .map { |m| [ m.credit_note_recap_grid, m.base_grid ] }
    pairs += snapshot.account_rules.select(&:credit_note_recap_grid).map { |r| [ r.credit_note_recap_grid, r.base_grid ] }
    pairs.group_by(&:first).transform_values { |v| v.map(&:last).uniq.sort }
  end

  def self.snapshot
    @snapshot ||= begin
      mappings = Accounting::VatGridMapping.includes(:vat_code).to_a
      raise NotSeeded, "VAT codes are not seeded — run Seeders::VatCodesSeeder (bin/rails db:seed)" if mappings.empty?

      Snapshot.new(mappings: mappings, account_rules: Accounting::VatAccountGridRule.all.to_a).freeze
    end
  end
  private_class_method :snapshot

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
