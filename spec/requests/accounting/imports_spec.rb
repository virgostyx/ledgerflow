require "rails_helper"

RSpec.describe "Accounting::Imports", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :accountant) }
  let(:day)        { (fiscal_year.start_date + 20).iso8601 }
  let!(:journal)   { create(:journal, code: "OD", journal_type: :misc) }

  before do
    create(:user_entity, :accountant, user: accountant, entity: entity)
    create(:user_entity, :assistant, user: assistant, entity: entity)
    sign_in accountant
  end

  def upload(csv, kind: "entries", **params)
    file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "pieces.csv")
    post accounting_imports_path, params: { file: file, kind: kind }.merge(params)
  end

  it "walks from the file to the drafts: read, map, check, import, take back" do
    upload(entries_csv([ balanced("A1", day), [ "A2", day, [ [ "604000", "5", "" ], [ "440000", "", "6" ] ] ] ]))
    batch = Accounting::ImportBatch.guided.last
    expect(response).to redirect_to(accounting_import_path(batch))

    follow_redirect!
    expect(response.body).to include("pieces.csv", "First rows of the file", "Check (writes nothing)")

    patch accounting_import_path(batch), params: { mapping: batch.mapping.merge("label" => ""), date_format: "iso", decimal: ".", template_name: "My ledger" }
    expect(ImportTemplate.find_by(name: "My ledger", kind: "entries").mapping).to include("piece" => "piece", "account" => "account")

    expect { post simulate_accounting_import_path(batch) }.not_to change(Accounting::JournalEntry, :count)
    follow_redirect!
    expect(response.body).to include("Simulation (nothing was written)", "does not balance")

    expect { post run_accounting_import_path(batch) }.to change(Accounting::JournalEntry, :count).by(1)
    expect(batch.reload).to have_attributes(result: "imported")
    get accounting_imports_path
    expect(response.body).to include("pieces.csv", "My ledger")

    expect { post undo_accounting_import_path(batch) }.to change(Accounting::JournalEntry, :count).by(-1)
    expect(batch.reload.result).to eq("undone")
  end

  it "saves the links chosen for the unknown values, which the next run uses" do
    upload(entries_csv([ [ "A1", day, [ [ "604999", "5", "" ], [ "440000", "", "5" ] ] ] ]))
    batch = Accounting::ImportBatch.guided.last
    post simulate_accounting_import_path(batch)
    get accounting_import_path(batch)
    expect(response.body).to include("Account 604999", "resolutions[accounts][604999]")

    patch accounting_import_path(batch), params: { mapping: batch.mapping, resolutions: { accounts: { "604999" => "604000" } } }
    post run_accounting_import_path(batch)
    expect(Accounting::JournalEntry.find_by(external_id: "A1")).to be_present
  end

  it "reads a file it can use and tells what is wrong with one it cannot" do
    upload("", kind: "partners")
    expect(flash[:alert]).to eq("The file is empty")
    post accounting_imports_path, params: { kind: "partners" }
    expect(flash[:alert]).to eq("Choose a file.")
    stub_const("Accounting::ImportsController::MAX_BYTES", 5)
    upload("name;type\nA;customer\n", kind: "partners")
    expect(flash[:alert]).to match(/larger than/)
  end

  it "runs the import of a large file in the background, and shows its progress" do
    stub_const("Imports::Run::BACKGROUND_ABOVE", 1)
    upload("name;type\nA;customer\nB;customer\n", kind: "partners")
    batch = Accounting::ImportBatch.guided.last
    expect { post run_accounting_import_path(batch) }.to have_enqueued_job(Imports::RunJob).with(batch.id, accountant.id)

    get accounting_import_path(batch)
    expect(response.body).to include("Running in the background", 'http-equiv="refresh"')
  end

  it "refuses to take back a batch of validated entries without a reason" do
    upload(entries_csv([ balanced("A1", day) ]))
    batch = Accounting::ImportBatch.guided.last
    post run_accounting_import_path(batch)
    Accounting::PostJournalEntry.call!(entry: Accounting::JournalEntry.find_by(external_id: "A1"))

    post undo_accounting_import_path(batch)
    expect(flash[:alert]).to match(/reason is required/)
    expect(batch.reload.result).to eq("imported")
  end

  it "is closed to those who may not import, and to an entity that did not turn the feature on" do
    sign_in create(:user, role: :auditor).tap { |u| create(:user_entity, :auditor, user: u, entity: entity) }
    get accounting_imports_path
    expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    expect { upload("name;type\nA;customer\n", kind: "partners") }.not_to change(Accounting::ImportBatch, :count)

    sign_in accountant
    entity.update!(features: { "f13" => false })
    get accounting_imports_path
    expect(response).to redirect_to(accounting_root_path)
  end

  it "does not show another entity's batches" do
    other = create(:entity)
    foreign = ActsAsTenant.with_tenant(other) { Accounting::ImportBatch.create!(parser: "guided_csv", file_sha256: "x", result: "uploaded", kind: "partners", filename: "theirs.csv") }
    get accounting_imports_path
    expect(response.body).not_to include("theirs.csv")
    get accounting_import_path(foreign)
    expect(response).to have_http_status(:not_found).or redirect_to(accounting_root_path)
  end
end
