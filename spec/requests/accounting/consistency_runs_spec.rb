require "rails_helper"

RSpec.describe "Accounting::ConsistencyRuns", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:auditor)    { create(:user, role: :auditor) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:auditor_membership)    { create(:user_entity, :auditor, user: auditor, entity: entity) }

  before { sign_in accountant }

  it "shows an empty state before the first run" do
    get accounting_consistency_runs_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No run yet")
  end

  it "runs on demand, shows the summary and the findings, and filters them" do
    bank  = create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit)
    entry = create(:journal_entry, :draft, journal: create(:journal, :purchase), fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 2)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: bank, debit: 10, credit: 0)

    post accounting_consistency_runs_path
    follow_redirect!
    expect(response.body).to include('id="consistency-summary"', "debit 10.0 ≠ credit 0.0")

    get accounting_consistency_runs_path(severity: "info")
    expect(response.body).not_to include("debit 10.0 ≠ credit 0.0")
  end

  it "acknowledges an anomaly with a comment and hides it afterwards; a blank comment is refused" do
    bank  = create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit)
    entry = create(:journal_entry, :draft, journal: create(:journal, :purchase), fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 2)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: bank, debit: 10, credit: 0)
    post accounting_consistency_runs_path
    fingerprint = Accounting::ConsistencyFinding.find_by!(check_id: "C01").fingerprint

    post acknowledge_accounting_consistency_runs_path, params: { fingerprint: fingerprint, comment: "" }
    expect(flash[:alert]).to be_present
    post acknowledge_accounting_consistency_runs_path, params: { fingerprint: fingerprint, comment: "Known" }
    expect(Accounting::ConsistencyAcknowledgement.find_by(fingerprint: fingerprint)).to have_attributes(comment: "Known", user_id: accountant.id)

    get accounting_consistency_runs_path
    expect(response.body).not_to include("debit 10.0 ≠ credit 0.0")
    get accounting_consistency_runs_path(acknowledged: "1")
    expect(response.body).to include("acknowledged: Known")
  end

  it "lets an auditor read the report but not run or acknowledge" do
    sign_out accountant
    sign_in auditor
    get accounting_consistency_runs_path
    expect(response).to have_http_status(:ok)
    expect { post accounting_consistency_runs_path }.not_to change(Accounting::ConsistencyRun, :count)
  end
end
