# Sale-side VAT codes + grid mappings (docs/dev/reports/spec.md §10), mirroring the
# rules already encoded in Accounting::VatGrid (RATE_TO_GRID[:sale], TREATMENT_BASE_GRID
# [:sale], VAT_LINE_GRID[:sale], SALE_CREDIT_VAT_GRID, #sale_credit_grid) — this seed is
# now their source of truth; see docs/dev/reports/QUESTIONS.md for why the purchase side
# isn't included.
module Seeders
  class VatCodesSeeder
    # [code, label, nature, rate, invoice_base_grid, credit_note_base_grid, due_vat_grid_on_invoice]
    # due_vat_grid is nil for a non-domestic nature (the partner self-assesses) and for the
    # 0%/exempt domestic rate; the credit_note due_vat_grid is always 64 when there is one.
    CODES = [
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

    def self.call
      new.call
    end

    def call
      counts = { created: 0, skipped: 0 }

      CODES.each do |code, label, nature, rate, invoice_grid, credit_note_grid, due_grid|
        vat_code = Accounting::VatCode.find_or_initialize_by(code: code)
        if vat_code.new_record?
          vat_code.assign_attributes(label: label, sens: :sale, nature: nature, rate: rate)
          vat_code.save!
          vat_code.grid_mappings.create!(document_type: :invoice, base_grid: invoice_grid, due_vat_grid: due_grid)
          vat_code.grid_mappings.create!(document_type: :credit_note, base_grid: credit_note_grid,
                                          due_vat_grid: due_grid && 64)
          counts[:created] += 1
        else
          counts[:skipped] += 1
        end
      end

      puts "[VatCodes] #{counts[:created]} codes créés, #{counts[:skipped]} déjà présents."
    end
  end
end
