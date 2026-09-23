require "rails_helper"

RSpec.describe "Accounting::FixedAssets", type: :request do
  include_context "with entity"

  let(:accountant) { create(:user, role: :accountant) }
  let(:admin)      { create(:user, role: :admin) }
  let(:auditor)    { create(:user, role: :auditor) }

  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:admin_membership)      { create(:user_entity, :admin,      user: admin,      entity: entity) }
  let!(:auditor_membership)    { create(:user_entity, :auditor,    user: auditor,    entity: entity) }

  before { sign_in accountant }

  describe "GET /accounting/fixed_assets" do
    it "returns 200" do
      get accounting_fixed_assets_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/fixed_assets/new" do
    it "returns 200" do
      get new_accounting_fixed_asset_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /accounting/fixed_assets" do
    let(:valid_attrs) do
      {
        description:            "Company van",
        acquisition_date:       Date.new(2026, 1, 15),
        vat_amount_initial:     "5000.00",
        prorata_at_acquisition: "80.00",
        asset_category:         "movable"
      }
    end

    it "creates a fixed asset and redirects" do
      expect {
        post accounting_fixed_assets_path, params: { accounting_fixed_asset: valid_attrs }
      }.to change(Accounting::FixedAsset, :count).by(1)
      expect(response).to redirect_to(accounting_fixed_assets_path)
    end

    it "returns 422 without a description" do
      post accounting_fixed_assets_path, params: { accounting_fixed_asset: valid_attrs.merge(description: "") }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /accounting/fixed_assets/:id/edit" do
    let(:asset) { create(:fixed_asset, entity: entity) }

    it "returns 200" do
      get edit_accounting_fixed_asset_path(asset)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /accounting/fixed_assets/:id" do
    let(:asset) { create(:fixed_asset, entity: entity, description: "Old description") }

    it "updates the asset and redirects" do
      patch accounting_fixed_asset_path(asset), params: { accounting_fixed_asset: { description: "New description" } }
      expect(response).to redirect_to(accounting_fixed_assets_path)
      expect(asset.reload.description).to eq("New description")
    end
  end

  describe "DELETE /accounting/fixed_assets/:id" do
    let!(:asset) { create(:fixed_asset, entity: entity) }

    it "deletes the asset as admin" do
      sign_in admin
      expect { delete accounting_fixed_asset_path(asset) }.to change(Accounting::FixedAsset, :count).by(-1)
    end

    it "refuses as accountant" do
      expect { delete accounting_fixed_asset_path(asset) }.not_to change(Accounting::FixedAsset, :count)
    end
  end

  describe "access as auditor (read-only)" do
    before { sign_in auditor }

    it "GET index returns 200" do
      get accounting_fixed_assets_path
      expect(response).to have_http_status(:ok)
    end

    it "POST create is refused" do
      post accounting_fixed_assets_path, params: { accounting_fixed_asset: { description: "x" } }
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
