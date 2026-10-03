require "rails_helper"

# F02: a big file (more than 10 000 records) is imported in the background, with a progress the screen can show. Same service, same
# guarantees (whole or nothing, never twice): only the waiting changes.
RSpec.describe "Importing a big CODA file in the background" do
  include_context "with entity"

  let(:user) { create(:user) }
  let(:acme) { CodaBuilder.iban("539007547034") }
  let!(:account) { create(:bank_account, iban: acme) }
  let(:bytes) { File.binread(Rails.root.join("spec/fixtures/files/coda/simple.cod")) }
  let(:memory) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(memory) }

  around do |example|
    previous = Rails.configuration.x.bank_import_background_lines
    example.run
  ensure
    Rails.configuration.x.bank_import_background_lines = previous
  end

  describe ".background?" do
    it "is true above the number of records the entity's setting allows (10 000 by default), judged on the size of the file" do
      expect(Rails.configuration.x.bank_import_background_lines).to eq(10_000)
      expect(Banking::ImportStatements.background?("x" * (128 * 10_000))).to be false
      expect(Banking::ImportStatements.background?("x" * (128 * 10_001))).to be true
    end
  end

  describe ".enqueue" do
    it "creates a batch that is processing, keeps the file for the job, and queues the job" do
      batch = nil
      expect { batch = Banking::ImportStatements.enqueue(bytes: bytes, user: user, source_name: "big.cod") }
        .to have_enqueued_job(Banking::ImportStatementsJob)

      expect(batch).to have_attributes(result: "processing", user: user, source_name: "big.cod", file_sha256: Digest::SHA256.hexdigest(bytes))
      expect(Accounting::BankTransaction.count).to eq(0)
    end
  end

  describe Banking::ImportStatementsJob do
    def run_job
      batch = Banking::ImportStatements.enqueue(bytes: bytes, user: user, source_name: "big.cod")
      described_class.perform_now(batch.id, entity.id)
      batch.reload
    end

    it "imports the file into the batch it was queued with, which becomes imported with its counts" do
      batch = run_job

      expect(batch).to have_attributes(result: "imported", statements_count: 1, lines_imported: 4, lines_read: 4)
      expect(Accounting::ImportBatch.count).to eq(1)
      expect(Accounting::BankTransaction.count).to eq(4)
      expect(Accounting::BankStatement.sole.import_batch).to eq(batch)
    end

    it "does not keep the queued copy of the file once it is stored as a document" do
      batch = run_job

      expect(batch.document).to be_present
      expect(batch.queued_file).not_to be_attached
    end

    it "rejects the batch, with the faulty lines, when the file is broken" do
      broken = bytes.split("\r\n").tap { |lines| lines[3] = lines[3][0, 90] }.join("\r\n")
      batch = Banking::ImportStatements.enqueue(bytes: broken, user: user, source_name: "broken.cod")

      described_class.perform_now(batch.id, entity.id)

      expect(batch.reload).to have_attributes(result: "rejected")
      expect(batch.errors_list.first).to include("line" => 4)
      expect(Accounting::ImportBatch.count).to eq(1)
      expect(Accounting::BankTransaction.count).to eq(0)
    end

    it "rejects a file that was imported in the meantime, saying so" do
      Banking::ImportStatements.call(bytes: bytes, user: user, source_name: "first.cod")
      batch = Banking::ImportStatements.enqueue(bytes: bytes, user: user, source_name: "again.cod")

      described_class.perform_now(batch.id, entity.id)

      expect(batch.reload.result).to eq("rejected")
      expect(batch.errors_list.first["text"]).to match(/already imported/i)
      expect(Accounting::BankTransaction.count).to eq(4)
    end

    it "does nothing for a batch that is no longer processing" do
      batch = run_job

      expect { described_class.perform_now(batch.id, entity.id) }.not_to change(Accounting::BankTransaction, :count)
    end
  end

  describe "the progress" do
    it "is written while the lines come in, and read as lines done over lines total" do
      batch = Banking::ImportStatements.enqueue(bytes: bytes, user: user, source_name: "big.cod")
      seen = []
      allow(memory).to receive(:write).and_wrap_original do |original, key, value, **options|
        seen << value if key == Banking::ImportStatements.progress_key(batch)
        original.call(key, value, **options)
      end

      Banking::ImportStatementsJob.perform_now(batch.id, entity.id)

      expect(seen.last).to include(done: 4, total: 4)
      expect(Banking::ImportStatements.progress(batch)).to include(done: 4, total: 4)
    end

    it "is unknown (nil) for a batch that has no progress" do
      expect(Banking::ImportStatements.progress(Accounting::ImportBatch.new(id: 0))).to be_nil
    end
  end
end
