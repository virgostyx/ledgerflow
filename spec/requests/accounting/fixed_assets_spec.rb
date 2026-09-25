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

    describe "disposal" do
      let!(:disposal_account) { create(:account, code: "660100", label_fr: "Moins-values", account_class: 6, account_type: :expense, normal_balance: :debit) }
      let!(:asset) { create(:fixed_asset, :depreciable, description: "Company laptops") }

      describe "GET /accounting/fixed_assets/:id/disposal" do
        it "shows the form with the date and the hint about the sales invoice" do
          get disposal_accounting_fixed_asset_path(asset)

          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Dispose of Company laptops", "760100", "Dispose")
        end

        it "redirects with an alert for an asset without depreciation setup" do
          get disposal_accounting_fixed_asset_path(create(:fixed_asset))

          expect(response).to redirect_to(accounting_fixed_assets_path)
          expect(flash[:alert]).to be_present
        end

        it "redirects with an alert for an asset already disposed of" do
          Accounting::DisposeFixedAsset.call(fixed_asset: asset, disposed_on: Date.new(2026, 12, 5))
          get disposal_accounting_fixed_asset_path(asset)

          expect(response).to redirect_to(accounting_fixed_assets_path)
          expect(flash[:alert]).to be_present
        end

        it "is refused to a read-only auditor" do
          sign_in auditor
          get disposal_accounting_fixed_asset_path(asset)
          expect(response).not_to have_http_status(:ok)
        end
      end

      describe "POST /accounting/fixed_assets/:id/dispose" do
        it "disposes of the asset and reports the net book value written off" do
          post dispose_accounting_fixed_asset_path(asset), params: { disposed_on: "2026-12-05" }

          expect(response).to redirect_to(accounting_fixed_assets_path)
          expect(flash[:notice]).to include("11 400,00 €")
          expect(asset.reload).to have_attributes(disposed_on: Date.new(2026, 12, 5))
          expect(asset.disposal_journal_entry).to be_posted
        end

        it "goes back to the form with the reason when the disposal is refused" do
          fy2026.update!(status: :closed, closed_at: Time.current)
          post dispose_accounting_fixed_asset_path(asset), params: { disposed_on: "2026-12-05" }

          expect(response).to redirect_to(disposal_accounting_fixed_asset_path(asset))
          expect(flash[:alert]).to be_present
          expect(asset.reload.disposed_on).to be_nil
        end

        it "refuses a missing or invalid date" do
          post dispose_accounting_fixed_asset_path(asset), params: { disposed_on: "" }

          expect(response).to redirect_to(disposal_accounting_fixed_asset_path(asset))
          expect(flash[:alert]).to be_present
          expect(Accounting::JournalEntry.count).to eq(0)
        end

        it "is refused to a read-only auditor" do
          sign_in auditor
          post dispose_accounting_fixed_asset_path(asset), params: { disposed_on: "2026-12-05" }
          expect(asset.reload.disposed_on).to be_nil
        end
      end

      describe "PATCH /accounting/fixed_assets/:id" do
        it "does not let the disposal date be typed on an asset that depreciates" do
          patch accounting_fixed_asset_path(asset), params: { accounting_fixed_asset: { disposed_on: "2026-12-05" } }

          expect(response).to have_http_status(:unprocessable_content)
          expect(asset.reload.disposed_on).to be_nil
        end
      end

      describe "GET /accounting/fixed_assets (Dispose link)" do
        it "offers Dispose for an asset that depreciates and is still held" do
          get accounting_fixed_assets_path
          expect(response.body).to include(disposal_accounting_fixed_asset_path(asset))
        end

        it "hides it once the asset is disposed of, and from an auditor" do
          sign_in auditor
          get accounting_fixed_assets_path
          expect(response.body).not_to include(disposal_accounting_fixed_asset_path(asset))

          sign_in accountant
          Accounting::DisposeFixedAsset.call(fixed_asset: asset, disposed_on: Date.new(2026, 12, 5))
          get accounting_fixed_assets_path
          expect(response.body).not_to include(disposal_accounting_fixed_asset_path(asset))
        end
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

  describe "from a purchase invoice line" do
    include_context "with_open_fiscal_year"
    include_context "with_pcmn_accounts"

    let!(:purchase_journal) { create(:journal, :purchase) }
    let!(:asset_account) { create(:account, code: "240200", label_fr: "Matériel informatique", account_class: 2, account_type: :asset, normal_balance: :debit) }
    let(:supplier) { create(:partner, :supplier) }

    def posted_purchase(account: asset_account, invoice_type: :supplier, post: true)
      inv = create(:invoice, invoice_type: invoice_type, partner: supplier, fiscal_year: fiscal_year,
                   journal: invoice_type == :supplier ? purchase_journal : create(:journal, :sale))
      create(:invoice_line, invoice: inv, account: account, quantity: 1, unit_price: "1000.00", vat_rate: "21.00",
             description: "Laptops for the team", position: 1)
      post ? Accounting::PostInvoice.call(invoice: inv).invoice.reload : inv
    end

    let(:line) { posted_purchase.lines.first }

    def field(name) = Nokogiri::HTML(response.body).at_css(%(input[name="accounting_fixed_asset[#{name}]"]))

    describe "GET /accounting/fixed_assets/new?invoice_line_id=" do
      it "prefills the form from the line" do
        get new_accounting_fixed_asset_path(invoice_line_id: line.id)

        expect(response).to have_http_status(:ok)
        expect(field("description")["value"]).to eq("Laptops for the team")
        expect(BigDecimal(field("acquisition_value")["value"])).to eq(BigDecimal("1000"))
        expect(BigDecimal(field("vat_amount_initial")["value"])).to eq(BigDecimal("210"))
        expect(field("invoice_line_id")["value"]).to eq(line.id.to_s)
        expect(field("asset_account_id")["value"]).to eq(asset_account.id.to_s)
      end

      it "shows where the asset comes from and does not let the account be changed" do
        get new_accounting_fixed_asset_path(invoice_line_id: line.id)

        expect(response.body).to include(line.invoice.invoice_number.to_s, "240200")
        expect(Nokogiri::HTML(response.body).at_css("select[name='accounting_fixed_asset[asset_account_id]']")).to be_nil
      end

      it "refuses a line that cannot become an asset, with an alert on its invoice" do
        expense_line = posted_purchase(account: account_604).lines.first
        get new_accounting_fixed_asset_path(invoice_line_id: expense_line.id)

        expect(response).to redirect_to(accounting_invoice_path(expense_line.invoice))
        expect(flash[:alert]).to be_present
      end

      it "refuses a draft invoice line" do
        draft_line = posted_purchase(post: false).lines.first
        get new_accounting_fixed_asset_path(invoice_line_id: draft_line.id)

        expect(response).to redirect_to(accounting_invoice_path(draft_line.invoice))
      end

      it "sends to the existing asset when the line already has one" do
        existing = create(:fixed_asset, invoice_line: line, asset_account: asset_account)
        get new_accounting_fixed_asset_path(invoice_line_id: line.id)

        expect(response).to redirect_to(edit_accounting_fixed_asset_path(existing))
      end

      it "goes back to the list for an unknown line" do
        get new_accounting_fixed_asset_path(invoice_line_id: 0)
        expect(response).to redirect_to(accounting_fixed_assets_path)
      end
    end

    describe "POST /accounting/fixed_assets" do
      let(:attrs) do
        { description: "Laptops for the team", acquisition_date: Date.current, vat_amount_initial: "210", prorata_at_acquisition: "100",
          asset_category: "movable", acquisition_value: "1000", asset_account_id: asset_account.id, useful_life_years: "3",
          invoice_line_id: line.id }
      end

      it "creates the asset linked to the line" do
        expect { post accounting_fixed_assets_path, params: { accounting_fixed_asset: attrs } }.to change(Accounting::FixedAsset, :count).by(1)

        expect(response).to redirect_to(accounting_fixed_assets_path)
        expect(Accounting::FixedAsset.last).to have_attributes(invoice_line: line, asset_account: asset_account)
      end

      it "refuses a second asset for the same line" do
        create(:fixed_asset, invoice_line: line, asset_account: asset_account)

        expect { post accounting_fixed_assets_path, params: { accounting_fixed_asset: attrs } }.not_to change(Accounting::FixedAsset, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "GET /accounting/fixed_assets (Invoice column)" do
      it "links an asset to the invoice it comes from" do
        create(:fixed_asset, description: "Team laptops", invoice_line: line, asset_account: asset_account)
        get accounting_fixed_assets_path

        expect(response.body).to include(accounting_invoice_path(line.invoice), line.invoice.invoice_number.to_s)
      end
    end

    describe "the invoice page" do
      it "offers Create fixed asset on a fixed asset line of an issued purchase" do
        get accounting_invoice_path(line.invoice)

        expect(response.body).to include("Create fixed asset", new_accounting_fixed_asset_path(invoice_line_id: line.id))
      end

      it "shows a link to the asset once created, instead" do
        asset = create(:fixed_asset, invoice_line: line, asset_account: asset_account)
        get accounting_invoice_path(line.invoice)

        expect(response.body).not_to include("Create fixed asset")
        expect(response.body).to include(edit_accounting_fixed_asset_path(asset))
      end

      it "offers nothing on an expense line, a draft, a sale or to a read-only auditor" do
        get accounting_invoice_path(posted_purchase(account: account_604).lines.first.invoice)
        expect(response.body).not_to include("Create fixed asset")

        get accounting_invoice_path(posted_purchase(post: false).lines.first.invoice)
        expect(response.body).not_to include("Create fixed asset")

        sign_in auditor
        get accounting_invoice_path(line.invoice)
        expect(response.body).not_to include("Create fixed asset")
      end
    end
  end
end
