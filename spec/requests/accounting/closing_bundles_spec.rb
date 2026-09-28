require "rails_helper"

RSpec.describe "Accounting::ClosingBundles", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before { sign_in accountant }

  it "renders the page with the three downloads" do
    get accounting_closing_bundle_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Download closing bundle", "Download audit export", "Download filing data")
  end

  it "downloads a verifiable bundle and records the export in the audit trail" do
    expect { get bundle_accounting_closing_bundle_path }.to change { Accounting::AuditLog.where(action: "export_closing_bundle").count }.by(1)
    expect(response.media_type).to eq("application/zip")
    expect(Accounting::ClosingBundle.verify(response.body)).to be_valid
  end

  it "downloads the audit export and the filing data" do
    get audit_export_accounting_closing_bundle_path
    expect(Accounting::Zipper.read(response.body).keys).to include("entries.csv", "accounts.json")
    get filing_data_accounting_closing_bundle_path
    expect(JSON.parse(response.body)).to include("fiscal_year", "balance_sheet", "vat_declarations")
    expect(Accounting::AuditLog.where(action: %w[export_audit_export export_filing_data]).count).to eq(2)
  end
end
