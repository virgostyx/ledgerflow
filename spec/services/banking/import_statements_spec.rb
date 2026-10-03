require "rails_helper"

# F02: importing a statement file. Atomic (the whole file or nothing), idempotent (a file, then a line, is never taken
# twice), chained and checked (a gap flags the statement, it never blocks).
RSpec.describe Banking::ImportStatements do
  include_context "with entity"

  CODA_DIR = Rails.root.join("spec/fixtures/files/coda")

  let(:user)     { create(:user) }
  let(:acme)     { CodaBuilder.iban("539007547034") }
  let!(:account) { create(:bank_account, iban: acme) }

  def bytes(name) = File.binread(CODA_DIR.join("#{name}.cod"))
  def import(name_or_bytes, **options) = described_class.call(bytes: name_or_bytes.is_a?(String) && !name_or_bytes.include?("\n") ? bytes(name_or_bytes) : name_or_bytes, user: user, source_name: "#{name_or_bytes}.cod", **options)
  def transactions = Accounting::BankTransaction.order(:id)

  describe "a simple statement" do
    let!(:result) { import("simple") }

    it "succeeds and tells what it did" do
      expect(result).to be_success
      expect(result[:statements].size).to eq(1)
      expect(result[:imported]).to eq(4)
      expect(result[:skipped]).to eq(0)
    end

    it "creates the movements as bank transactions, signed, dated and described" do
      credit = transactions.first

      expect(transactions.count).to eq(4)
      expect(credit).to have_attributes(bank_account: account, transaction_date: Date.new(2026, 3, 2), value_date: Date.new(2026, 3, 2), amount: BigDecimal("1210.00"),
                                        currency: "EUR", status: "pending", transaction_code: "00150000", bank_reference: "BKREF0000000000000001")
      expect(transactions.second.amount).to eq(BigDecimal("-605.00"))
    end

    it "keeps the counterparty and the communication, structured or free" do
      credit = transactions.first

      expect(credit).to have_attributes(counterparty_name: "DUPONT ET FILS SPRL", counterparty_iban: CodaBuilder.iban("091012345678"), structured_communication: Accounting::StructuredCommunication.for_id(1))
      expect(credit.description).to include(Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(1)))
      expect(transactions.second.description).to eq("FACTURE F-2026-0042 BUREAU PLUS")
    end

    it "does not use the bank's reference as the reference of the transaction (it is only informative and can repeat)" do
      expect(transactions.map(&:reference).uniq).to eq([ nil ])
    end

    it "keeps the records as the bank sent them, and a fingerprint" do
      expect(transactions.first.raw_data["records"].map { |r| r[0, 2] }).to eq(%w[21 22 23])
      expect(transactions.map(&:fingerprint).uniq.size).to eq(4)
    end

    it "creates the statement with its balances and ties the movements to it" do
      statement = Accounting::BankStatement.sole

      expect(statement).to have_attributes(bank_account: account, sequence: 12, old_balance: BigDecimal("1000.00"), new_balance: BigDecimal("1842.50"),
                                           old_balance_date: Date.new(2026, 3, 1), new_balance_date: Date.new(2026, 3, 31), status: "ok", integrity_gap: 0, chain_gap: nil)
      expect(statement.transactions.count).to eq(4)
    end

    it "records the batch: who, which file, how many lines" do
      batch = Accounting::ImportBatch.sole

      expect(batch).to have_attributes(user: user, parser: "coda", result: "imported", file_sha256: Digest::SHA256.hexdigest(bytes("simple")),
                                       statements_count: 1, lines_read: 4, lines_imported: 4, lines_skipped: 0, source_name: "simple.cod")
      expect(Accounting::BankStatement.sole.import_batch).to eq(batch)
    end

    it "audits the import without keeping any content, the IBAN masked" do
      row = Accounting::AuditLog.where(action: "bank_statement_import").sole

      expect(row.user_id).to eq(user.id)
      expect(row.payload).to include("file_sha256" => Digest::SHA256.hexdigest(bytes("simple")), "lines_imported" => 4)
      expect(row.payload.to_s).not_to include(acme, "DUPONT")
      expect(row.payload.to_s).to include(acme.last(4))
    end

    it "stores the file in the document store, as a statement that came from the bank import" do
      document = Accounting::ImportBatch.sole.document

      expect(document).to have_attributes(kind: "statement", origin: "bank_import", sha256: Digest::SHA256.hexdigest(bytes("simple")))
      expect(document.file.download).to eq(bytes("simple"))
    end
  end

  describe "the matching engine on what comes in" do
    let!(:bank_gl)    { create(:account, code: "550000", label_fr: "Banque", account_class: 5, account_type: :asset, normal_balance: :debit) }
    let!(:receivable) { create(:account, code: "400000", label_fr: "Clients", account_type: :asset, normal_balance: :debit) }
    let(:fiscal_year) { create(:fiscal_year, status: :open) }
    let(:partner)     { create(:partner, name: "DUPONT ET FILS SPRL", iban: CodaBuilder.iban("091012345678")) }
    let(:invoice)     { create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: partner).tap { |i| i.update_columns(total_incl_vat: BigDecimal("1210")) } }

    def file_with(movement) = CodaBuilder.file(statements: [ { iban: acme, sequence: 1, date: Date.new(2026, 3, 31), movements: [ movement ] } ])

    it "books a draft payment for an exact match, and tells it" do
      account.journal.update!(default_account: bank_gl)

      result = import(file_with(amount: "1210.00", structured: CodaBuilder.structured(invoice.id), bank_reference: "EXACT0000000000000001", counterparty_name: "X"))

      expect(result).to be_success
      expect(result[:drafted]).to eq(1)
      expect(transactions.sole).to be_matched
      expect(transactions.sole.journal_entry).to be_draft
    end

    it "keeps a suggestion for a good but not exact match, and tells it" do
      invoice

      result = import(file_with(amount: "1210.00", free: "PAYMENT", bank_reference: "GOOD00000000000000001", counterparty_iban: partner.iban, counterparty_name: "X"))

      expect(result[:suggested]).to eq(1)
      expect(transactions.sole).to be_pending
      expect(transactions.sole.match_data).to include("score" => 90)
    end

    it "never fails the import because of the engine" do
      allow(Banking::AutoMatch).to receive(:call).and_raise("engine down")

      result = import("simple")

      expect(result).to be_success
      expect(transactions.count).to eq(4)
      expect(result[:warnings].join).to include("engine down")
    end
  end

  describe "a file imported twice" do
    it "is refused with a pointer to the first import, and nothing changes" do
      import("simple")

      result = nil
      expect { result = import("simple") }.not_to change { [ Accounting::BankTransaction.count, Accounting::BankStatement.count ] }

      expect(result).to be_failure
      expect(result[:reason]).to eq(:already_imported)
      expect(result.message).to match(/already imported on .* by #{Regexp.escape(user.email)}/i)
    end

    it "is not refused because an earlier attempt of it was rejected" do
      lines = bytes("simple").split("\r\n")
      broken = (lines[0..1] + [ lines[2][0, 100] ] + lines[3..]).join("\r\n")
      expect(import(broken)).to be_failure

      expect(Accounting::ImportBatch.where(result: "rejected").count).to eq(1)
      expect(import(broken)).to be_failure # the same broken file is refused again, for its own reason
      expect(import("simple")).to be_success
    end
  end

  describe "a file that is refused" do
    it "is refused whole when it is broken, with the faulty lines, and leaves a rejected batch" do
      result = import("broken_length")

      expect(result).to be_failure
      expect(result[:reason]).to eq(:invalid_file)
      expect(result[:errors].map(&:line)).to include(4)
      expect(Accounting::BankTransaction.count).to eq(0)
      expect(Accounting::ImportBatch.sole).to have_attributes(result: "rejected", file_sha256: Digest::SHA256.hexdigest(bytes("broken_length")))
      expect(Accounting::ImportBatch.sole.errors_list.first).to include("line" => 4)
    end

    it "is refused when its account is not one of the entity's bank accounts, naming it masked, and imports nothing of it" do
      account.update!(iban: CodaBuilder.iban("001234567890"))

      result = import("simple")

      expect(result).to be_failure
      expect(result[:reason]).to eq(:unknown_account)
      expect(result.message).to include(acme.last(4))
      expect(result.message).not_to include(acme)
      expect(Accounting::BankStatement.count).to eq(0)
    end

    it "is refused whole when only one of its accounts is unknown (nothing is imported by halves)" do
      expect(import("two_accounts")).to be_failure # the savings account is not declared

      expect(Accounting::BankTransaction.count).to eq(0)
      expect(Accounting::BankStatement.count).to eq(0)
    end

    it "is refused when the currency of the statement is not the one of the bank account" do
      account.update!(iban: acme)
      other = create(:bank_account, iban: CodaBuilder.iban("539000000001"), currency: "EUR")

      result = import("usd_account")

      expect(other).to be_persisted
      expect(result[:reason]).to eq(:currency_mismatch)
      expect(Accounting::BankTransaction.count).to eq(0)
    end

    it "is refused when it is empty or not a CODA file at all" do
      expect(import("not_coda")[:reason]).to eq(:invalid_file)
      expect(described_class.call(bytes: "", user: user, source_name: "x.cod")[:reason]).to eq(:invalid_file)
    end

    it "takes back everything when one line cannot be written (atomic)" do
      allow(Accounting::BankTransaction).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        raise ActiveRecord::RecordInvalid, Accounting::BankTransaction.new if Accounting::BankTransaction.count >= 2

        original.call(*args, **kwargs)
      end

      result = import("simple")

      expect(result).to be_failure
      expect(Accounting::BankTransaction.count).to eq(0)
      expect(Accounting::BankStatement.count).to eq(0)
      expect(Accounting::ImportBatch.sole.result).to eq("rejected")
    end
  end

  describe "several accounts in one file" do
    it "imports each statement apart" do
      create(:bank_account, iban: CodaBuilder.iban("310123456789"))

      result = import("two_accounts")

      expect(result).to be_success
      expect(Accounting::BankStatement.count).to eq(2)
      expect(result[:imported]).to eq(5)
      expect(Accounting::ImportBatch.sole.statements_count).to eq(2)
    end
  end

  describe "statements that overlap" do
    it "imports only the new lines of the second, recognised by their fingerprint" do
      import("overlap_a")

      result = import("overlap_b")

      expect(result[:imported]).to eq(1)
      expect(result[:skipped]).to eq(2)
      expect(Accounting::BankTransaction.count).to eq(3)
      expect(Accounting::BankStatement.count).to eq(2)
      expect(Accounting::ImportBatch.order(:id).last).to have_attributes(lines_read: 3, lines_imported: 1, lines_skipped: 2)
    end

    it "takes two identical lines of one file as two movements, and does not duplicate them when a later file repeats them" do
      twin = { amount: "10.00", bank_reference: "TWIN0000000000000001", free: "CARD", counterparty_name: "SHOP", value_date: Date.new(2026, 3, 4) }
      first  = CodaBuilder.file(statements: [ { iban: acme, sequence: 1, date: Date.new(2026, 3, 5), movements: [ twin, twin ] } ])
      second = CodaBuilder.file(statements: [ { iban: acme, sequence: 2, date: Date.new(2026, 3, 6), old_balance: "0.00", movements: [ twin, twin, twin.merge(amount: "5.00") ] } ])

      expect(import(first)[:imported]).to eq(2)
      result = import(second)

      expect(result[:imported]).to eq(1)
      expect(Accounting::BankTransaction.count).to eq(3)
    end
  end

  describe "chaining the statements" do
    it "has no gap when the opening balance is the closing balance of the previous statement" do
      import("chain_a")
      import("chain_b_continues")

      expect(Accounting::BankStatement.order(:new_balance_date).last).to have_attributes(chain_gap: BigDecimal("0"), status: "ok")
      expect(Accounting::BankStatement.order(:new_balance_date).first.chain_gap).to be_nil
    end

    it "flags a break, with its amount, without blocking the import" do
      import("chain_a")

      result = import("chain_b_break")

      expect(result).to be_success
      statement = Accounting::BankStatement.order(:new_balance_date).last
      expect(statement.chain_gap).to eq(BigDecimal("849.00"))
      expect(statement).to be_chain_broken
      expect(result[:warnings].join).to match(/849/)
      expect(Accounting::BankTransaction.count).to eq(2)
    end
  end

  describe "checking a statement against its movements" do
    it "marks a statement that does not add up as to review, with the gap, and imports its lines all the same" do
      result = import("integrity_mismatch")

      expect(result).to be_success
      statement = Accounting::BankStatement.sole
      expect(statement).to be_to_review
      expect(statement.integrity_gap).to eq(BigDecimal("3713.05"))
      expect(result[:warnings].join).to match(/does not add up/i)
      expect(Accounting::BankTransaction.count).to eq(4)
    end
  end

  describe "an account without movement" do
    it "is a statement with no line and no new balance, and the import succeeds" do
      result = import("empty_account")

      expect(result).to be_success
      expect(Accounting::BankStatement.sole).to have_attributes(old_balance: BigDecimal("1234.56"), new_balance: nil, status: "ok")
      expect(Accounting::BankTransaction.count).to eq(0)
    end
  end

  describe "at the same moment" do
    it "imports a file once when two people send it together", :concurrency do
      user # created before the threads start
      results = concurrently(-> { import("simple") }, -> { import("simple") }, entity: entity)

      expect(results.count(&:success?)).to eq(1)
      expect(Accounting::BankTransaction.count).to eq(4)
      expect(Accounting::ImportBatch.imported.count).to eq(1)
    end
  end
end
