require "rails_helper"

RSpec.describe Seeders::VatCodesSeeder do
  def seed
    expect { described_class.call }.to output(/\[VatCodes\]/).to_stdout
  end

  it "creates every sale-side VAT code with its invoice and credit-note grid mapping" do
    expect { seed }.to change(Accounting::VatCode, :count).by(described_class::CODES.size)
    expect(Accounting::VatGridMapping.count).to eq(described_class::CODES.size * 2)
  end

  it "matches the rates and grids already used by Accounting::VatGrid" do
    seed
    code21 = Accounting::VatCode.find_by!(code: "SALE-21")
    expect(code21.rate).to eq(21)
    expect(code21.grid_mappings.find_by!(document_type: :invoice)).to have_attributes(base_grid: 3, due_vat_grid: 54)
    expect(code21.grid_mappings.find_by!(document_type: :credit_note)).to have_attributes(base_grid: 49, due_vat_grid: 64)

    intracom = Accounting::VatCode.find_by!(code: "SALE-INTRACOM-GOODS")
    expect(intracom.grid_mappings.find_by!(document_type: :invoice)).to have_attributes(base_grid: 46, due_vat_grid: nil)
    expect(intracom.grid_mappings.find_by!(document_type: :credit_note)).to have_attributes(base_grid: 48, due_vat_grid: nil)
  end

  it "is idempotent" do
    seed
    expect { seed }.not_to change(Accounting::VatCode, :count)
  end
end
