require "rails_helper"

RSpec.describe "Guided import of partners and accounts" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user) { create(:user, role: :accountant) }

  before { create(:user_entity, :accountant, user: user, entity: entity) }

  describe "partners" do
    it "creates the valid rows, skips those already there (same VAT, reference or name) and refuses the others with their line" do
      create(:partner, name: "Existing Ltd", vat_number: "BE0123456749")
      csv = <<~CSV
        name;type;vat_number;email;payment_terms_days
        Acme SA;customer;BE0417497106;billing@acme.test;45
        Existing Other Name;supplier;BE 0123.456.749;;
        existing ltd;customer;;;
        ;customer;;;
        Weird;friend;;;
        Fresh Supplies;supplier;;;
        Acme SA;customer;;;
      CSV
      batch = run_import(start_import("partners", csv, user: user), user: user)

      expect(batch.summary).to include("created" => 2, "skipped" => 3, "refused" => 2)
      expect(Accounting::Partner.where(import_batch_id: batch.id).order(:name).pluck(:name, :partner_type, :payment_terms_days))
        .to eq([ [ "Acme SA", "customer", 45 ], [ "Fresh Supplies", "supplier", 30 ] ])
      expect(batch.errors_list.map { |e| [ e["lines"], e["message"] ] }).to eq([ [ [ 5 ], "the name is missing" ], [ [ 6 ], "the type \"friend\" is not customer, supplier or both" ] ])
    end

    it "refuses a row the partner itself finds invalid" do
      batch = run_import(start_import("partners", "name;type;vat_number\nBad VAT;customer;BE123\n", user: user), user: user)
      expect(batch.errors_list.first["message"]).to match(/vat/i)
    end

    it "is taken back by deleting what it created, and keeps a partner that an entry uses" do
      batch = run_import(start_import("partners", "name;type\nA;customer\nB;supplier\n", user: user), user: user)
      used = Accounting::Partner.find_by(name: "A")
      entry = create(:journal_entry, :draft, journal: create(:journal), fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_400, partner: used, debit: 5, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: account_700, debit: 0, credit: 5)

      Imports::Undo.call(batch: batch, user: user)
      expect(Accounting::Partner.where(name: %w[A B]).pluck(:name)).to eq([ "A" ])
      expect(Accounting::AuditLog.where(action: "guided_import_undone").last.payload["kept"]).to eq([ "partner A" ])
    end
  end

  describe "accounts" do
    it "creates custom accounts under the parent named or the longest prefix, and refuses what has no parent" do
      csv = <<~CSV
        code;label_fr;parent_code;reconcilable
        6040001;Sub-contracting;;
        60400011;Sub-contracting BE;6040001;yes
        999000;Orphan;;
        604000;Already there;;
        60;Short;;
      CSV
      batch = run_import(start_import("accounts", csv, user: user), user: user)

      expect(batch.summary).to include("created" => 2, "skipped" => 1, "refused" => 2)
      created = Accounting::Account.where(import_batch_id: batch.id).order(:code)
      expect(created.map { |a| [ a.code, a.parent&.code, a.custom, a.account_class, a.account_type, a.reconcilable ] })
        .to eq([ [ "6040001", "604000", true, 6, "expense", false ], [ "60400011", "6040001", true, 6, "expense", true ] ])
      expect(batch.errors_list.map { |e| [ e["ref"], e["message"] ] }).to eq([ [ "999000", "no parent account: no account starts the code" ], [ "60", "no parent account: no account starts the code" ] ])
    end
  end

  it "asks for a complete mapping before reading anything, and uses a saved template" do
    batch = start_import("partners", "Customer name;Kind\nA;customer\n", user: user)
    expect(batch.mapping).to eq({})
    expect(run_import(batch, user: user).errors_list.first["message"]).to eq("Map a column to: name, type")
    expect(batch.reload.result).to eq("uploaded")

    template = ImportTemplate.create!(name: "My ERP", kind: "partners", mapping: { "name" => "Customer name", "type" => "Kind" })
    batch = run_import(start_import("partners", "Customer name;Kind\nA;customer\n", user: user, template: template), user: user)
    expect(batch.summary).to include("created" => 1)
  end

  it "refuses a file it cannot read" do
    expect { start_import("partners", "", user: user) }.to raise_error(Imports::Reader::Unreadable)
    expect { start_import("nonsense", "a\n1\n", user: user) }.to raise_error(Imports::Reader::Unreadable, /Unknown kind/)
  end

  it "runs a long import in chunks and shows its progress", :aggregate_failures do
    stub_const("Imports::Run::CHUNK", 2)
    csv = "name;type\n" + (1..5).map { |i| "P#{i};customer" }.join("\n") + "\n"
    batch = run_import(start_import("partners", csv, user: user), user: user)
    expect(batch).to have_attributes(result: "imported", lines_imported: 5)
    expect(Accounting::Partner.where(import_batch_id: batch.id).count).to eq(5)
  end

  it "runs through the job for a large file, in the entity of the batch" do
    batch = start_import("partners", "name;type\nBackground;customer\n", user: user)
    ActsAsTenant.without_tenant { Imports::RunJob.perform_now(batch.id, user.id) }
    expect(batch.reload.result).to eq("imported")
  end
end
