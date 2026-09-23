require "rails_helper"

RSpec.describe "Accounting::FiscalYears — VAT regularization", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)     { create(:user, role: :manager) }

  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager,    user: manager,    entity: entity) }
  let!(:misc_journal)          { create(:journal, journal_type: :misc) }
  let!(:purchase_journal)      { create(:journal, :purchase) }

  before do
    entity.update!(vat_prorata_rate: "70.00")
    sign_in accountant
  end

  def post_purchase_invoice(unit_price:)
    partner = create(:partner)
    inv = create(:invoice, invoice_type: :supplier, partner: partner, fiscal_year: fiscal_year, journal: purchase_journal)
    create(:invoice_line, invoice: inv, account: account_604, quantity: 1, unit_price: unit_price, vat_rate: "21.00", position: 1)
    inv.compute_totals
    inv.save!
    Accounting::PostInvoice.call(invoice: inv)
  end

  describe "GET /accounting/fiscal_years/:id/vat_regularization" do
    it "retourne 200" do
      get vat_regularization_accounting_fiscal_year_path(fiscal_year)
      expect(response).to have_http_status(:ok)
    end

    it "liste les immobilisations encore en période de révision" do
      asset = create(:fixed_asset, entity: entity, description: "Machine à café",
                     acquisition_date: fiscal_year.start_date, asset_category: :movable)
      get vat_regularization_accounting_fiscal_year_path(fiscal_year)
      expect(response.body).to include(asset.description)
    end

    it "refuse l accès à un manager" do
      sign_in manager
      get vat_regularization_accounting_fiscal_year_path(fiscal_year)
      expect(response).to redirect_to(accounting_root_path)
    end
  end

  describe "POST /accounting/fiscal_years/:id/regularize_prorata" do
    before { post_purchase_invoice(unit_price: "1000.00") } # 210 VAT, 147 deducted at 70%

    it "poste une régularisation et redirige" do
      expect {
        post regularize_prorata_accounting_fiscal_year_path(fiscal_year), params: { final_prorata_rate: "90" }
      }.to change(Accounting::JournalEntry, :count).by(1)
      expect(response).to redirect_to(vat_regularization_accounting_fiscal_year_path(fiscal_year))
    end

    it "n effectue aucune écriture si le taux final correspond au prorata déjà appliqué" do
      expect {
        post regularize_prorata_accounting_fiscal_year_path(fiscal_year), params: { final_prorata_rate: "70" }
      }.not_to change(Accounting::JournalEntry, :count)
    end

    it "renvoie une alerte sur un taux invalide" do
      post regularize_prorata_accounting_fiscal_year_path(fiscal_year), params: { final_prorata_rate: "abc" }
      expect(response).to redirect_to(vat_regularization_accounting_fiscal_year_path(fiscal_year))
      follow_redirect!
      expect(response.body).to include("Invalid")
    end
  end

  describe "POST /accounting/fiscal_years/:id/review_fixed_assets" do
    let!(:asset) do
      create(:fixed_asset, entity: entity, description: "Machine à café",
             acquisition_date: fiscal_year.start_date, asset_category: :movable,
             vat_amount_initial: "1000.00", prorata_at_acquisition: "70.00")
    end

    it "révise les immobilisations éligibles et redirige avec un résumé" do
      expect {
        post review_fixed_assets_accounting_fiscal_year_path(fiscal_year), params: { final_prorata_rate: "90" }
      }.to change(Accounting::JournalEntry, :count).by(1)
      expect(response).to redirect_to(vat_regularization_accounting_fiscal_year_path(fiscal_year))
      follow_redirect!
      expect(response.body).to include("1")
    end
  end
end
