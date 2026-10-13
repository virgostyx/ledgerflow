require "rails_helper"

# B01b: how each bank takes its payment file. The version of the format comes from the bank, never from a guess: the owner records it, and says whether a file was seen to be taken.
RSpec.describe "Bank profiles for payment files (B01b)", type: :request do
  include_context "with entity"

  let(:owner)  { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:reader) { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:params) do
    { payment_bank_profile: { name: "Crelan", format_version: "pain.001.001.03", max_payments: "500", max_batch_total: "250000", max_supplier_total: "", balance_threshold: "1000",
                              closed_days: "2026-12-24, 2026-12-31", format_verified: "0", coda_verified: "0" } }
  end

  before { sign_in owner }

  it "is closed when the feature is off, and to those who do not manage the settings" do
    sign_in reader
    get accounting_settings_payment_bank_profiles_path
    expect(response).to redirect_to(accounting_root_path)

    sign_in owner
    entity.update!(features: entity.features.merge("b01b" => false))
    get accounting_settings_payment_bank_profiles_path
    expect(response).to redirect_to(accounting_root_path)
  end

  it "records a profile with its limits and closed days, and says it was not verified yet" do
    post accounting_settings_payment_bank_profiles_path, params: params

    profile = Payments::BankProfile.last
    expect(profile).to have_attributes(name: "Crelan", format_version: "pain.001.001.03", max_payments: 500, max_batch_total: 250_000, max_supplier_total: nil, balance_threshold: 1000, format_verified: false)
    expect(profile.options["closed_days"]).to eq(%w[2026-12-24 2026-12-31])
    get accounting_settings_payment_bank_profiles_path
    expect(response.body).to include("Crelan").and include("not verified")
    expect(Accounting::AuditLog.for_record(profile).for_action("create")).to exist
  end

  it "takes only a version the builder knows, and a date that is a date" do
    post accounting_settings_payment_bank_profiles_path, params: { payment_bank_profile: params[:payment_bank_profile].merge(format_version: "pain.001.001.09") }
    expect(response).to have_http_status(:unprocessable_content)

    post accounting_settings_payment_bank_profiles_path, params: { payment_bank_profile: params[:payment_bank_profile].merge(closed_days: "tomorrow") }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Payments::BankProfile.count).to eq(0)
  end

  it "is edited, and what is said verified is in the audit trail" do
    profile = Payments::BankProfile.create!(name: "Crelan", format_version: "pain.001.001.03")

    patch accounting_settings_payment_bank_profile_path(profile), params: { payment_bank_profile: { format_verified: "1" } }

    expect(profile.reload).to be_format_verified
    log = Accounting::AuditLog.for_record(profile).for_action("update").last
    expect(log.payload["changes"]).to include("format_verified" => [ false, true ])
    expect(log.user_id).to eq(owner.id)
  end
end
