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

  describe "depreciation" do
    let!(:fy2026) { create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :open) }
    let!(:misc_journal) { create(:journal, journal_type: :misc) }
    let!(:asset_account) do
      create(:account, code: "240200", label_fr: "Matériel informatique", account_class: 2, account_type: :asset, normal_balance: :debit)
    end
    let!(:expense_account)     { create(:account, code: "630200", account_class: 6, account_type: :expense, normal_balance: :debit) }
    let!(:accumulated_account) { create(:account, code: "249000", account_class: 2, account_type: :asset, normal_balance: :credit) }

    let(:depreciation_attrs) do
      { description: "Company laptops", acquisition_date: "2026-10-01", vat_amount_initial: "0", prorata_at_acquisition: "100",
        asset_category: "movable", acquisition_value: "12000.00", asset_account_id: asset_account.id,
        in_service_date: "2026-10-15", useful_life_years: "5", residual_value: "0" }
    end

    describe "POST /accounting/fixed_assets" do
      it "stores the depreciation setup" do
        post accounting_fixed_assets_path, params: { accounting_fixed_asset: depreciation_attrs }

        expect(response).to redirect_to(accounting_fixed_assets_path)
        expect(Accounting::FixedAsset.last).to have_attributes(acquisition_value: BigDecimal("12000"), asset_account: asset_account,
                                                               in_service_date: Date.new(2026, 10, 15), useful_life_years: 5)
      end

      it "returns 422 when a value is given without a useful life" do
        post accounting_fixed_assets_path, params: { accounting_fixed_asset: depreciation_attrs.merge(useful_life_years: "") }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "GET /accounting/fixed_assets/new" do
      it "offers the depreciable asset accounts only" do
        create(:account, code: "220100", label_fr: "Terrains", account_class: 2, account_type: :asset, normal_balance: :debit)
        create(:account, code: "604000", label_fr: "Services divers")
        get new_accounting_fixed_asset_path

        expect(response.body).to include("240200")
        expect(response.body).not_to include("220100")
        expect(response.body).not_to include("604000")
      end
    end

    describe "GET /accounting/fixed_assets/:id/edit" do
      it "shows the depreciation plan" do
        asset = create(:fixed_asset, :depreciable)
        get edit_accounting_fixed_asset_path(asset)

        expect(response.body).to include("Depreciation plan", "2026", "600,00 €", "2031", "1 800,00 €", "0,00 €")
      end

      it "shows no plan for an asset without depreciation setup" do
        get edit_accounting_fixed_asset_path(create(:fixed_asset))
        expect(response.body).not_to include("Depreciation plan")
      end
    end

    describe "GET /accounting/fixed_assets (depreciation of the fiscal year)" do
      let!(:asset) { create(:fixed_asset, :depreciable, description: "Company laptops") }

      it "lists what is pending for the open fiscal year, with the button" do
        get accounting_fixed_assets_path

        expect(response.body).to include("Depreciation 2026", "Company laptops", "600,00 €", "Pending", "Post depreciation")
      end

      it "shows it as posted, without the button, once booked" do
        Accounting::PostDepreciation.call(fiscal_year: fy2026)
        get accounting_fixed_assets_path

        expect(response.body).to include("Posted")
        expect(response.body).not_to include("Post depreciation")
      end

      it "hides the button from a read-only auditor" do
        sign_in auditor
        get accounting_fixed_assets_path
        expect(response.body).not_to include("Post depreciation")
      end

      it "shows no depreciation section when nothing is depreciable" do
        asset.destroy
        get accounting_fixed_assets_path
        expect(response.body).not_to include("Depreciation 2026")
      end
    end

    describe "DELETE /accounting/fixed_assets/:id" do
      it "keeps an asset that has already been depreciated and says why" do
        asset = create(:fixed_asset, :depreciable)
        Accounting::PostDepreciation.call(fiscal_year: fy2026)
        sign_in admin

        expect { delete accounting_fixed_asset_path(asset) }.not_to change(Accounting::FixedAsset, :count)

        expect(response).to redirect_to(accounting_fixed_assets_path)
        expect(flash[:alert]).to be_present
      end
    end

    describe "POST /accounting/fixed_assets/post_depreciation" do
      let!(:asset) { create(:fixed_asset, :depreciable) }

      it "posts the depreciation and redirects with a notice" do
        expect { post post_depreciation_accounting_fixed_assets_path, params: { fiscal_year_id: fy2026.id } }
          .to change(Accounting::DepreciationEntry, :count).by(1)

        expect(response).to redirect_to(accounting_fixed_assets_path)
        expect(flash[:notice]).to include("600,00 €")
      end

      it "says so when there is nothing left to post" do
        Accounting::PostDepreciation.call(fiscal_year: fy2026)
        post post_depreciation_accounting_fixed_assets_path, params: { fiscal_year_id: fy2026.id }

        expect(flash[:notice]).to be_present
        expect(Accounting::DepreciationEntry.count).to eq(1)
      end

      it "refuses a closed fiscal year with an alert" do
        fy2026.update!(status: :closed, closed_at: Time.current)
        post post_depreciation_accounting_fixed_assets_path, params: { fiscal_year_id: fy2026.id }

        expect(flash[:alert]).to be_present
        expect(Accounting::DepreciationEntry.count).to eq(0)
      end

      it "is refused to a read-only auditor" do
        sign_in auditor
        expect { post post_depreciation_accounting_fixed_assets_path, params: { fiscal_year_id: fy2026.id } }
          .not_to change(Accounting::DepreciationEntry, :count)
      end
    end
  end
end
