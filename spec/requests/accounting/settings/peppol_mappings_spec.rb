require "rails_helper"

# F06 step 4, settings: how each UBL VAT category is treated (an unmapped one makes a message wait), and the account proposed per supplier.
RSpec.describe "Peppol mappings", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:owner)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let!(:owner_membership)      { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }

  before { sign_in owner } # the Peppol configuration is the owner's (decided 2026-10-05)

  it "shows the categories, S, Z, E and O ready and the others not mapped" do
    get edit_accounting_settings_peppol_mappings_path

    expect(response.body).to include("VAT categories of the UBL").and include("Not mapped")
    expect(Accounting::VatCategoryMapping.pluck(:category)).to match_array(%w[S Z E O])
  end

  it "maps a category with the rate to self-assess, and audits it" do
    patch accounting_settings_peppol_mappings_path, params: { mappings: { "AE" => { vat_treatment: "construction_reverse_charge", vat_rate: "21" } } }

    expect(Accounting::VatCategoryMapping.find_by(category: "AE")).to have_attributes(vat_treatment: "construction_reverse_charge", vat_rate: 21)
    expect(Accounting::AuditLog.where(auditable_type: "Accounting::VatCategoryMapping", user_id: owner.id)).to exist
  end

  it "unmaps a category left empty, and it does not come back" do
    get edit_accounting_settings_peppol_mappings_path
    patch accounting_settings_peppol_mappings_path, params: { mappings: { "E" => { vat_treatment: "" } } }
    get edit_accounting_settings_peppol_mappings_path

    expect(Accounting::VatCategoryMapping.pluck(:category)).to match_array(%w[S Z O])
  end

  it "changes how a category is treated" do
    get edit_accounting_settings_peppol_mappings_path
    patch accounting_settings_peppol_mappings_path, params: { mappings: { "E" => { vat_treatment: "exempt" } } }

    expect(Accounting::VatCategoryMapping.find_by(category: "E")).to be_exempt
  end

  it "ignores a category that is not a UBL one" do
    patch accounting_settings_peppol_mappings_path, params: { mappings: { "X" => { vat_treatment: "domestic" } } }

    expect(Accounting::VatCategoryMapping.find_by(category: "X")).to be_nil
  end

  it "changes the account proposed for a supplier" do
    supplier = create(:partner, partner_type: :supplier)
    default = Accounting::SupplierDefault.create!(partner: supplier, account: account_604)
    other = create(:account, code: "612000", label_fr: "Other", account_class: 6, entity: entity)

    get edit_accounting_settings_peppol_mappings_path
    expect(response.body).to include(supplier.name)

    patch accounting_settings_peppol_mappings_path, params: { defaults: { default.id => { account_id: other.id } } }

    expect(default.reload.account).to eq(other)
  end

  it "is closed to an accountant and to an assistant: only the owner configures" do
    sign_in accountant
    get edit_accounting_settings_peppol_settings_path
    expect(response).not_to have_http_status(:ok)
    patch accounting_settings_peppol_mappings_path, params: { mappings: { "AE" => { vat_treatment: "domestic" } } }
    expect(Accounting::VatCategoryMapping.find_by(category: "AE")).to be_nil

    sign_in assistant
    get edit_accounting_settings_peppol_mappings_path

    expect(response).not_to have_http_status(:ok)
    patch accounting_settings_peppol_mappings_path, params: { mappings: { "AE" => { vat_treatment: "domestic" } } }
    expect(Accounting::VatCategoryMapping.find_by(category: "AE")).to be_nil
  end

  it "links from the Peppol settings, which the same rights open" do
    get edit_accounting_settings_peppol_settings_path

    expect(response.body).to include(edit_accounting_settings_peppol_mappings_path)
  end
end
