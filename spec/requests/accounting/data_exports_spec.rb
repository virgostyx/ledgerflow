require "rails_helper"

RSpec.describe "Accounting::DataExports", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:owner)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let(:reader)     { create(:user, role: :auditor) }
  let!(:journal)   { create(:journal, code: "OD", journal_type: :misc) }

  before do
    create(:user_entity, :admin, user: owner, entity: entity)
    create(:user_entity, :accountant, user: accountant, entity: entity)
    create(:user_entity, :manager, user: reader, entity: entity)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 10, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_440, debit: 0, credit: 10)
    Accounting::PostJournalEntry.call!(entry: entry)
    sign_in accountant
  end

  it "streams a dataset as CSV, JSON or XLSX, with its schema version, and records it in the audit trail" do
    get accounting_data_export_file_path(dataset: "entries", as: "csv", from: fiscal_year.start_date.iso8601)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("attachment", "entries-v1.csv")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(CSV.parse(response.body, headers: true).size).to eq(2)

    get accounting_data_export_file_path(dataset: "accounts", as: "json")
    expect(JSON.parse(response.body)).to include("schema_version" => 1, "dataset" => "accounts")

    get accounting_data_export_file_path(dataset: "journals", as: "xlsx")
    expect(Imports::Reader.read(response.body, filename: "x.xlsx").headers.first).to eq("schema_version")

    log = Accounting::AuditLog.where(action: "data_export").order(:id).first
    expect(log).to have_attributes(user_id: accountant.id)
    expect(log.payload).to include("dataset" => "entries", "format" => "csv", "from" => fiscal_year.start_date.iso8601)
    expect(Accounting::AuditLog.where(action: "data_export").count).to eq(3)
  end

  it "refuses a format or a dataset it does not know, and a period that runs backwards" do
    get accounting_data_export_file_path(dataset: "entries", as: "pdf")
    expect(response).to have_http_status(:not_found)
    get accounting_data_export_file_path(dataset: "secrets", as: "csv")
    expect(flash[:alert]).to match(/Unknown dataset/)
    get accounting_data_export_file_path(dataset: "entries", as: "csv", from: "2026-05-01", to: "2026-04-01")
    expect(flash[:alert]).to match(/before/)
    get accounting_data_export_file_path(dataset: "entries", as: "csv", from: "not a date")
    expect(response).to have_http_status(:redirect)
  end

  it "points to the CSV when an XLSX would be too big" do
    stub_const("Exports::Standard::XLSX_MAX_ROWS", 1)
    get accounting_data_export_file_path(dataset: "entries", as: "xlsx")
    expect(flash[:alert]).to match(/CSV/)
  end

  it "is closed to a read-only role, and to an entity without the feature" do
    sign_in reader
    get accounting_data_export_file_path(dataset: "entries", as: "csv")
    expect(response).not_to have_http_status(:ok)
    expect(Accounting::AuditLog.where(action: "data_export")).to be_empty

    sign_in accountant
    entity.update!(features: { "f13" => false })
    get accounting_data_exports_path
    expect(response).to redirect_to(accounting_root_path)
  end

  it "keeps the full backup to the owner: asked, built, then downloaded through a signed link" do
    get accounting_data_exports_path
    expect(response.body).not_to include("Build a backup")
    post backup_accounting_data_exports_path
    expect(DataExport.count).to eq(0)

    sign_in owner
    get accounting_data_exports_path
    expect(response.body).to include("Build a backup")
    expect { post backup_accounting_data_exports_path }.to have_enqueued_job(Exports::BackupJob)
    export = DataExport.last

    post backup_accounting_data_exports_path
    expect(flash[:alert]).to match(/already being built/)

    Exports::BackupJob.perform_now(export.id)
    get accounting_data_exports_path
    expect(response.body).to include("Ready", "/accounting/data_exports/download/")

    get download_accounting_data_exports_path(token: export.reload.link_token)
    expect(response.headers["Content-Type"]).to include("application/zip")
    expect(Exports::Backup.verify(response.body)).to be_valid
    expect(Accounting::AuditLog.where(action: %w[backup_requested backup_downloaded]).order(:id).pluck(:action)).to eq(%w[backup_requested backup_downloaded])
  end

  it "refuses an expired or forged link, and the link of another entity's backup" do
    sign_in owner
    export = DataExport.create!(user: owner, kind: "backup")
    Exports::Backup.call(data_export: export)

    token = export.reload.link_token
    travel(2.hours) do
      get download_accounting_data_exports_path(token: token)
      expect(flash[:alert]).to match(/expired/)
    end
    get download_accounting_data_exports_path(token: "forged")
    expect(flash[:alert]).to match(/expired/)

    other_entity = create(:entity)
    foreign = ActsAsTenant.with_tenant(other_entity) { DataExport.create!(kind: "backup", status: "ready", entity: other_entity) }
    get download_accounting_data_exports_path(token: foreign.link_token)
    expect(flash[:alert]).to match(/expired/)
  end
end
