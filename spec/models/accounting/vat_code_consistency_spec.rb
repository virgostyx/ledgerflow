require "rails_helper"

# accounting_vat_codes/accounting_vat_grid_mappings (docs/dev/reports/spec.md §10) are
# seeded to MIRROR Accounting::VatGrid's sale-side Ruby constants — deliberately not yet
# the live source Accounting::Actions::GenerateInvoiceJournalEntry reads from (see
# docs/dev/reports/QUESTIONS.md: making that switch means those constants become DB
# queries evaluated at class-load time, memoized for the process, which would silently
# break on any fresh boot before the seed runs — too risky for VAT filing without a
# separately-scoped change to how they're loaded). This spec is the drift guard: if
# either side changes without updating the other, it fails.
RSpec.describe "VAT code / Accounting::VatGrid consistency", type: :model do
  before { Seeders::VatCodesSeeder.call }

  it "has one seeded code per domestic sale rate, matching RATE_TO_GRID[:sale]" do
    Accounting::VatGrid::RATE_TO_GRID[:sale].each do |rate, grid|
      code = Accounting::VatCode.find_by!(nature: :domestic, rate: rate)
      expect(code.grid_mappings.find_by!(document_type: :invoice).base_grid).to eq(grid)
    end
  end

  it "matches TREATMENT_BASE_GRID[:sale] for every non-domestic nature" do
    Accounting::VatGrid::TREATMENT_BASE_GRID[:sale].each do |treatment, grid|
      code = Accounting::VatCode.find_by!(nature: treatment)
      expect(code.grid_mappings.find_by!(document_type: :invoice).base_grid).to eq(grid)
    end
  end

  it "matches VAT_LINE_GRID[:sale] on every domestic rate above zero" do
    Accounting::VatCode.where(nature: :domestic).where.not(rate: 0).find_each do |code|
      expect(code.grid_mappings.find_by!(document_type: :invoice).due_vat_grid)
        .to eq(Accounting::VatGrid::VAT_LINE_GRID[:sale])
    end
  end

  it "matches #sale_credit_grid and SALE_CREDIT_VAT_GRID for every credit note mapping" do
    Accounting::VatCode.find_each do |code|
      mapping = code.grid_mappings.find_by!(document_type: :credit_note)
      expect(mapping.base_grid).to eq(Accounting::VatGrid.sale_credit_grid(code.nature))
      expect(mapping.due_vat_grid).to eq(code.domestic? && code.rate.positive? ? Accounting::VatGrid::SALE_CREDIT_VAT_GRID : nil)
    end
  end
end
