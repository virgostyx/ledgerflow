require "rails_helper"

# B03c étape 1, critère 1: two computations of the fingerprint of an entry give the same fingerprint, any change of a field of its content changes it, what changes legitimately
# after the validation (lettering, residual, links) does not; it is written when the entry is validated, in the same transaction, and the database never lets it change.
RSpec.describe "The fingerprint of the content of an entry" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user) }
  let(:partner) { create(:partner, name: "Acme") }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4, reconcilable: true) }

  def draft(amount: 100, **attrs)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: nil, description: "Invoice", **attrs)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0, label: "Services", sort_order: 1, vat_code: 82, vat_amount: 21)
    create(:journal_entry_line, journal_entry: entry, account: payable, partner: partner, debit: 0, credit: amount, label: "Acme", sort_order: 2, due_date: fiscal_year.start_date + 40)
    entry
  end

  def post(entry)
    result = Current.set(user: user) { Accounting::PostJournalEntry.call(entry: entry) }
    raise result.message if result.failure?

    entry.reload
  end

  def digest(entry) = Ledger::EntryContent.digest(entry)

  describe "the content" do
    it "is canonical JSON: sorted, amounts as decimal strings, nothing that changes after the validation" do
      entry = post(draft)

      content = Ledger::EntryContent.canonical(entry)

      expect(content).to include("entity_id" => entity.id, "journal_id" => journal.id, "entry_date" => entry.entry_date.iso8601, "reference" => entry.reference, "posted_seq" => entry.posted_seq,
                                 "posted_at" => entry.posted_at.utc.iso8601(6), "posted_by_id" => user.id)
      expect(content["lines"].map { |l| l.slice("account_id", "debit", "credit", "label") }).to eq([
        { "account_id" => expense.id, "debit" => "100.00", "credit" => "0.00", "label" => "Services" },
        { "account_id" => payable.id, "debit" => "0.00", "credit" => "100.00", "label" => "Acme" }
      ])
      expect(content["lines"].first).to include("vat_code" => 82, "vat_amount" => "21.00", "currency" => "EUR", "amount_currency" => nil, "n" => 1)
      expect(content["lines"].last).to include("due_date" => (fiscal_year.start_date + 40).iso8601, "partner_id" => partner.id)
      expect(content.keys).not_to include("status", "lettering_id")
      expect(content["lines"].flat_map(&:keys)).not_to include("lettering_id", "amount_residual", "invoice_id")
    end
  end

  describe "the fingerprint" do
    it "is written when the entry is validated, in that transaction, as 'live', with the author of the validation" do
      entry = post(draft)

      expect(entry.content_hash).to match(/\A[0-9a-f]{64}\z/)
      expect(entry.content_hash_source).to eq("live")
      expect(entry.posted_by_id).to eq(user.id)
      expect(entry.content_hash).to eq(digest(entry))
    end

    it "is the same every time it is computed, and has nothing in it of the clock of the computation" do
      entry = post(draft)

      expect(Array.new(3) { digest(entry.reload) }.uniq.size).to eq(1)
      travel_to(1.year.from_now) { expect(digest(entry.reload)).to eq(entry.content_hash) }
    end

    it "leaves a draft without one" do
      expect(draft.content_hash).to be_nil
    end

    it "does not change when the entry is lettered, reversed (its status) or its lines get a residual: those change legitimately" do
      entry = post(draft)
      before = entry.content_hash
      entry.lines.each { |l| l.update_columns(amount_residual: 5, lettering_id: nil, disputed: true) }
      Accounting::ReverseJournalEntry.call(entry: entry, reason: "mistake", user: user)

      expect(entry.reload).to be_reversed
      expect(entry.content_hash).to eq(before)
      expect(digest(entry)).to eq(before)
    end

    it "is written for the reversal too, with the link to the original in its content" do
      original = post(draft)
      reversal = Accounting::ReverseJournalEntry.call(entry: original, reason: "mistake", user: user)[:reversal].reload

      expect(reversal.content_hash).to eq(digest(reversal))
      expect(Ledger::EntryContent.canonical(reversal)).to include("reversal_of_id" => original.id)
    end

    it "changes with every field of the content (a property over the fields)" do
      entry = post(draft)
      line = entry.lines.order(:sort_order).first
      variants = {
        "reference" => -> { entry.update_columns(reference: "OTHER") },
        "description" => -> { entry.update_columns(description: "Other") },
        "entry_date" => -> { entry.update_columns(entry_date: entry.entry_date + 1) },
        "journal" => -> { entry.update_columns(journal_id: create(:journal, :misc, code: "ZZ").id) },
        "debit" => -> { line.update_columns(debit: 100.01) },
        "account" => -> { line.update_columns(account_id: payable.id) },
        "label" => -> { line.update_columns(label: "Changed") },
        "vat_code" => -> { line.update_columns(vat_code: 54) },
        "vat_amount" => -> { line.update_columns(vat_amount: 20) },
        "currency" => -> { line.update_columns(currency: "USD") },
        "due_date" => -> { line.update_columns(due_date: Date.new(2030, 1, 1)) },
        "partner" => -> { line.update_columns(partner_id: create(:partner, name: "Other").id) },
        "order" => -> { line.update_columns(sort_order: 9) },
        "posted_at" => -> { tamper(:accounting_journal_entries) { entry.update_columns(posted_at: 1.year.ago) } },
        "posted_seq" => -> { tamper(:accounting_journal_entries) { entry.update_columns(posted_seq: 999) } }
      }
      base = entry.content_hash

      variants.each do |field, change|
        ApplicationRecord.transaction(requires_new: true) do
          change.call
          expect(digest(entry.reload)).not_to eq(base), "changing #{field} did not change the fingerprint"
          raise ActiveRecord::Rollback
        end
      end
    end

    it "takes no amount as a float: 0.1 + 0.2 never gets in" do
      entry = post(draft(amount: BigDecimal("0.30")))

      expect(Ledger::EntryContent.canonical(entry)["lines"].first["debit"]).to eq("0.30")
    end
  end

  describe "what the database allows" do
    it "refuses to change or remove the fingerprint, or to put one on a draft, or to change who validated" do
      entry = post(draft)
      other = create(:user)

      [ -> { entry.update_columns(content_hash: "a" * 64) }, -> { entry.update_columns(content_hash: nil, content_hash_source: nil) }, -> { entry.update_columns(content_hash_source: "retroactive") },
        -> { entry.update_columns(posted_by_id: other.id) }, -> { draft.update_columns(content_hash: "b" * 64, content_hash_source: "live") } ].each do |attempt|
        expect { ApplicationRecord.transaction(requires_new: true) { attempt.call } }.to raise_error(ActiveRecord::StatementInvalid, /content_hash|posted_by_id|not validated/)
      end
    end

    it "refuses what is not a fingerprint" do
      entry = draft
      expect { ApplicationRecord.transaction(requires_new: true) { entry.update_columns(content_hash: "xyz", content_hash_source: "live") } }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "an entry validated before the fingerprints existed" do
    it "gets one afterwards, as 'retroactive', once, and the same as it would have had" do
      entry = post(draft)
      tamper(:accounting_journal_entries) { entry.update_columns(content_hash: nil, content_hash_source: nil) }
      expected = digest(entry.reload)

      Ledger::Seal.call(entry, source: "retroactive")

      expect(entry.reload).to have_attributes(content_hash: expected, content_hash_source: "retroactive")
      expect(Ledger::Seal.call(entry, source: "retroactive")).to be(false) # already has one
    end

    it "is not sealed while it has no line (a validated entry whose lines are still to come)" do
      entry = create(:journal_entry, :posted, fiscal_year: fiscal_year, journal: journal, reference: "BARE-1")

      expect(entry.reload.content_hash).to be_nil
      expect(Ledger::Seal.call(entry, source: "retroactive")).to be(false)
    end
  end
end
