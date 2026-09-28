# VAT codes, grid mappings and account-prefix rules (docs/dev/reports/spec.md §10) — the
# single source Accounting::VatGrid reads. Grid numbers follow the SPF Finances notice
# (docs/dev/notice explicative TVA.pdf): credit notes are reported in their own grids, never
# netted from the original operation's (notice n°98, 252).
module Seeders
  class VatCodesSeeder
    # sale: [code, label, nature, rate, invoice base, credit-note base, VAT due grid (nil = none)]
    SALE = [
      [ "SALE-21", "Domestic sale at 21%", :domestic, 21, 3, 49, 54 ],
      [ "SALE-12", "Domestic sale at 12%", :domestic, 12, 2, 49, 54 ],
      [ "SALE-06", "Domestic sale at 6%",  :domestic, 6,  1, 49, 54 ],
      [ "SALE-00", "Domestic sale at 0% (exempt by article)", :domestic, 0, 0, 49, nil ],
      [ "SALE-INTRACOM-GOODS",    "Intracommunity supply of goods",     :intracom_goods, nil, 46, 48, nil ],
      [ "SALE-INTRACOM-SERVICES", "Intracommunity service supplied",    :intracom_services, nil, 44, 48, nil ],
      [ "SALE-REVERSE-CHARGE",    "Reverse-charge sale (construction)", :construction_reverse_charge, nil, 45, 49, nil ],
      [ "SALE-EXPORT",            "Export / other exempt sale",         :export, nil, 47, 49, nil ],
      [ "SALE-EXEMPT",            "Other exempt sale (article 44)",     :exempt, nil, 0, 49, nil ]
    ].freeze
    SALE_CREDIT_VAT_GRID = 64

    # purchase: [code, label, nature, base grid (nil = by account), self-assessed VAT due grid,
    #            credit-note due grid, credit-note recap grid]
    PURCHASE = [
      [ "PURCHASE-DOMESTIC", "Domestic purchase", :domestic, nil, nil, nil, nil ],
      [ "PURCHASE-INTRACOM-GOODS",    "Intracommunity acquisition of goods", :intracom_goods, 86, 55, 62, 84 ],
      [ "PURCHASE-INTRACOM-SERVICES", "Intracommunity service received",    :intracom_services, 88, 55, 62, 84 ],
      [ "PURCHASE-REVERSE-CHARGE",    "Other reverse-charge purchase",       :construction_reverse_charge, 87, 56, 62, 85 ]
    ].freeze
    DEDUCTIBLE = { invoice: 59, credit_note_domestic: 63, credit_note_reverse_charge: 61 }.freeze

    # [account prefix, base grid, credit-note recap grid]
    ACCOUNT_RULES = [ [ "60", 81, 85 ], [ "61", 82, 85 ], [ "64", 82, 85 ],
                      *("20".."27").map { |p| [ p, 83, 85 ] } ].freeze

    def self.call = new.call

    def call
      created = 0
      SALE.each { |row| created += 1 if seed_sale(*row) }
      PURCHASE.each { |row| created += 1 if seed_purchase(*row) }
      ACCOUNT_RULES.each do |prefix, grid, recap|
        Accounting::VatAccountGridRule.find_or_create_by!(sens: :purchase, account_prefix: prefix) do |r|
          r.base_grid = grid
          r.credit_note_recap_grid = recap
        end
      end
      Accounting::VatGrid.reset!
      puts "[VatCodes] #{created} codes créés, #{SALE.size + PURCHASE.size - created} déjà présents."
    end

    private

    def seed_sale(code, label, nature, rate, invoice_grid, credit_note_grid, due_grid)
      seed(code, label, :sale, nature, rate) do |vat_code|
        vat_code.grid_mappings.create!(document_type: :invoice, base_grid: invoice_grid, due_vat_grid: due_grid)
        vat_code.grid_mappings.create!(document_type: :credit_note, base_grid: credit_note_grid,
                                        due_vat_grid: due_grid && SALE_CREDIT_VAT_GRID)
      end
    end

    def seed_purchase(code, label, nature, base_grid, due_grid, credit_due_grid, recap_grid)
      seed(code, label, :purchase, nature, nil) do |vat_code|
        domestic = nature == :domestic
        vat_code.grid_mappings.create!(document_type: :invoice, base_grid: base_grid, due_vat_grid: due_grid,
                                        deductible_vat_grid: DEDUCTIBLE[:invoice])
        vat_code.grid_mappings.create!(
          document_type: :credit_note, base_grid: base_grid, due_vat_grid: credit_due_grid,
          deductible_vat_grid: domestic ? DEDUCTIBLE[:credit_note_domestic] : DEDUCTIBLE[:credit_note_reverse_charge],
          credit_note_recap_grid: recap_grid
        )
      end
    end

    def seed(code, label, sens, nature, rate)
      vat_code = Accounting::VatCode.find_or_initialize_by(code: code)
      return false unless vat_code.new_record?

      vat_code.assign_attributes(label: label, sens: sens, nature: nature, rate: rate)
      vat_code.save!
      yield vat_code
      true
    end
  end
end
