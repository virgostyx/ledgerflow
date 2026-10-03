require "rails_helper"

RSpec.describe "Accounting::BankStatements", type: :request do
  include_context "with entity"

  CODA_FILES = Rails.root.join("spec/fixtures/files/coda") unless defined?(CODA_FILES)

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let(:reader)     { create(:user, role: :auditor) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let!(:reader_membership)     { create(:user_entity, :manager, user: reader, entity: entity) }
  let(:acme) { CodaBuilder.iban("539007547034") }
  let!(:account) { create(:bank_account, iban: acme, label_fr: "Compte courant ACME") }

  def coda(name) = Rack::Test::UploadedFile.new(CODA_FILES.join("#{name}.cod"), "text/plain", true)
  def upload(name) = post(accounting_bank_statements_path, params: { file: coda(name) })

  before { sign_in accountant }

  describe "importing a CODA file" do
    it "shows the form" do
      get new_accounting_bank_statement_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("CODA")
    end

    it "imports it, then says what came in" do
      expect { upload("simple") }.to change(Accounting::BankTransaction, :count).by(4)

      expect(response).to redirect_to(accounting_bank_statements_path)
      expect(flash[:notice]).to match(/4 lines imported/i)
    end

    it "tells how many lines the engine drafted or suggested" do
      upload("simple")

      expect(flash[:notice]).to match(/drafted|suggestion/i)
    end

    it "refuses a broken file whole and lists its faulty lines" do
      expect { upload("broken_length") }.not_to change(Accounting::BankTransaction, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("line 4", "130 characters instead of 128")
    end

    it "refuses a file already imported, pointing to the first import" do
      upload("simple")

      expect { upload("simple") }.not_to change(Accounting::BankTransaction, :count)

      expect(response.body).to match(/already imported/i)
    end

    it "refuses the account of a file that is not a bank account of the entity, the IBAN masked" do
      account.update!(iban: CodaBuilder.iban("001234567890"))

      upload("simple")

      expect(response.body).to include(acme.last(4))
      expect(response.body).not_to include(acme)
    end

    it "asks for a file" do
      post accounting_bank_statements_path

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is refused to an assistant, who matches lines but does not import" do
      sign_out accountant
      sign_in assistant

      expect { upload("simple") }.not_to change(Accounting::BankTransaction, :count)
    end

    it "is closed while the feature is off" do
      entity.update!(features: entity.features.merge("f02" => false))

      get new_accounting_bank_statement_path

      expect(response).to redirect_to(accounting_root_path)
    end
  end

  describe "a big file, imported in the background" do
    let(:memory) { ActiveSupport::Cache::MemoryStore.new }

    around do |example|
      previous = Rails.configuration.x.bank_import_background_lines
      Rails.configuration.x.bank_import_background_lines = 5 # records: the sample file has more
      example.run
    ensure
      Rails.configuration.x.bank_import_background_lines = previous
    end

    before { allow(Rails).to receive(:cache).and_return(memory) }

    it "is queued, not imported, and the list says that it is in progress" do
      expect { upload("simple") }.to have_enqueued_job(Banking::ImportStatementsJob)

      expect(Accounting::BankTransaction.count).to eq(0)
      expect(flash[:notice]).to match(/background/i)
      follow_redirect!
      expect(response.body).to include("Import in progress", "simple.cod", 'http-equiv="refresh"')
    end

    it "shows how far it is" do
      upload("simple")
      batch = Accounting::ImportBatch.sole
      memory.write(Banking::ImportStatements.progress_key(batch), { done: 50, total: 200 })

      get accounting_bank_statements_path

      expect(response.body).to include("25 %", "50 of 200 lines")
    end

    it "is gone from the list, and the statements are there, once the job has run" do
      upload("simple")
      batch = Accounting::ImportBatch.sole
      Banking::ImportStatementsJob.perform_now(batch.id, entity.id)

      get accounting_bank_statements_path

      expect(response.body).not_to include("Import in progress")
      expect(response.body).not_to include('http-equiv="refresh"')
      expect(Accounting::BankStatement.count).to eq(1)
    end

    it "shows a background import that was refused among the refused files, with its lines" do
      broken = CODA_FILES.join("broken_length.cod")
      post accounting_bank_statements_path, params: { file: Rack::Test::UploadedFile.new(broken, "text/plain", true) }
      Banking::ImportStatementsJob.perform_now(Accounting::ImportBatch.sole.id, entity.id)

      get accounting_bank_statements_path

      expect(response.body).to include("Files that were refused", "line 4")
    end
  end

  describe "the statements" do
    it "lists them with the account, the balances and the file's date" do
      upload("simple")

      get accounting_bank_statements_path

      expect(response.body).to include("Compte courant ACME", "1 000,00", "1 842,50").or include("1000.00", "1842.50")
    end

    it "marks a statement that does not add up as to review, with its gap, and a break in the chain with its amount" do
      upload("chain_a")
      upload("chain_b_break")
      upload("integrity_mismatch")

      get accounting_bank_statements_path

      expect(response.body).to match(/to review/i)
      expect(response.body).to match(/849/)
    end

    it "is readable by a reader, who cannot import" do
      upload("simple")
      sign_out accountant
      sign_in reader

      get accounting_bank_statements_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(new_accounting_bank_statement_path)
    end

    it "shows one statement with its lines" do
      upload("simple")

      get accounting_bank_statement_path(Accounting::BankStatement.sole)

      expect(response.body).to include("DUPONT ET FILS SPRL", "FACTURE F-2026-0042")
    end

    it "does not show another entity's statement" do
      other = create(:entity)
      foreign = ActsAsTenant.with_tenant(other) do
        other_account = create(:bank_account, entity: other)
        batch = Accounting::ImportBatch.create!(parser: "coda", file_sha256: "x", result: "imported")
        Accounting::BankStatement.create!(bank_account: other_account, import_batch: batch, old_balance: 0)
      end

      get accounting_bank_statement_path(foreign)

      expect(response).to have_http_status(:not_found)
    end
  end
end
