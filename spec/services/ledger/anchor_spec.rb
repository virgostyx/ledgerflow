require "rails_helper"
require Rails.root.join("tools/ledger-verify/lib/ledger_verify/merkle")

# B03c étape 2, critère 2 (I17): the Merkle root recomputed from the entries of an anchor is the one recorded, and the chain of anchors is unbroken. An anchor binds the entries
# validated since the previous one, the head of the audit chain and the previous anchor.
RSpec.describe Ledger::Anchor do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user) }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  def post_entry(amount = 10)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    result = Current.set(user: user) { Accounting::PostJournalEntry.call(entry: entry) }
    raise result.message if result.failure?

    entry.reload
  end

  def hashes(from, to) = Accounting::JournalEntry.where(posted_seq: from..to).order(:posted_seq).pluck(:content_hash)

  describe ".create!" do
    it "binds the entries validated so far: bounds, count, Merkle root over their fingerprints in the order of validation, head of the audit chain" do
      entries = Array.new(3) { post_entry }
      chained = Accounting::AuditLog.unscoped.where(entity_id: entity.id).where.not(content_hash: nil).order(:id)

      anchor = Ledger::Anchoring.call(kind: "nightly")

      expect(anchor).to have_attributes(number: 1, kind: "nightly", from_seq: 1, to_seq: 3, entries_count: 3, previous_anchor_hash: nil, retroactive_entries: 0)
      expect(anchor.merkle_root).to eq(LedgerVerify::Merkle.root_of_hex(entries.map(&:content_hash)))
      expect(anchor.audit_head).to eq(chained.last.content_hash) # the anchor itself writes nothing in the audit chain: it would never stop moving
      expect(anchor.audit_length).to eq(chained.count)
      expect(anchor.anchored_at).to be_within(5.seconds).of(Time.current)
    end

    it "has an anchor hash that covers the previous anchor, the bounds, the root, the count, the head of the audit chain and the date (canonical JSON)" do
      post_entry
      anchor = Ledger::Anchoring.call(kind: "on_demand")

      expected = Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate("anchored_at" => anchor.anchored_at.utc.iso8601(6), "audit_head" => anchor.audit_head, "audit_length" => anchor.audit_length,
                                                                          "count" => 1, "from_seq" => 1, "previous" => nil, "root" => anchor.merkle_root, "to_seq" => 1))
      expect(anchor.anchor_hash).to eq(expected)
      expect(described_class.hash_of(anchor)).to eq(expected)
    end

    it "goes on from the previous anchor: the next range, linked by its hash" do
      post_entry
      first = Ledger::Anchoring.call(kind: "nightly")
      2.times { post_entry }

      second = Ledger::Anchoring.call(kind: "nightly")

      expect(second).to have_attributes(number: 2, from_seq: 2, to_seq: 3, entries_count: 2, previous_anchor_hash: first.anchor_hash)
      expect(second.merkle_root).to eq(LedgerVerify::Merkle.root_of_hex(hashes(2, 3)))
    end

    it "makes none when nothing was validated and the audit chain did not move since the last one" do
      post_entry
      Ledger::Anchoring.call(kind: "nightly")

      expect(Ledger::Anchoring.call(kind: "nightly")).to be_nil
    end

    it "makes one when only the audit chain moved (a lock, a setting): it binds that too" do
      post_entry
      Ledger::Anchoring.call(kind: "nightly")
      Accounting::AuditLog.record!(auditable: fiscal_year, action: "something_happened")

      anchor = Ledger::Anchoring.call(kind: "nightly")

      expect(anchor).to have_attributes(number: 2, entries_count: 0, from_seq: 2, to_seq: 1)
      expect(anchor.merkle_root).to eq(Digest::SHA256.hexdigest("")) # nothing to bind but the audit chain
    end

    it "is refused when an entry has no fingerprint and cannot get one (no line), saying which" do
      post_entry
      bare = create(:journal_entry, :posted, fiscal_year: fiscal_year, journal: journal, reference: "BARE-9")

      expect { Ledger::Anchoring.call(kind: "nightly") }.to raise_error(Ledger::Anchoring::Refused, /#{bare.id}/)
      expect(described_class.count).to eq(0)
    end

    it "makes the retroactive anchor once, and only first" do
      post_entry
      Ledger::Anchoring.call(kind: "retroactive")
      post_entry

      expect { Ledger::Anchoring.call(kind: "retroactive") }.to raise_error(Ledger::Anchoring::Refused, /once|first/)
    end

    it "refuses an unknown kind" do
      expect { Ledger::Anchoring.call(kind: "weekly") }.to raise_error(ArgumentError)
    end
  end

  describe "an entry validated before the fingerprints existed" do
    it "is fingerprinted by the anchor, as retroactive, and the anchor says how many" do
      entries = Array.new(2) { post_entry }
      tamper(:accounting_journal_entries) { Accounting::JournalEntry.where(id: entries.first.id).update_all(content_hash: nil, content_hash_source: nil) }

      anchor = Ledger::Anchoring.call(kind: "retroactive")

      expect(entries.first.reload.content_hash_source).to eq("retroactive")
      expect(entries.last.reload.content_hash_source).to eq("live")
      expect(anchor).to have_attributes(kind: "retroactive", retroactive_entries: 1)
      expect(anchor.merkle_root).to eq(LedgerVerify::Merkle.root_of_hex(hashes(1, 2)))
    end
  end

  describe "the chain of anchors (I17)" do
    before do
      2.times { post_entry }
      Ledger::Anchoring.call(kind: "nightly")
      3.times { post_entry }
      Ledger::Anchoring.call(kind: "nightly")
      post_entry
      Ledger::Anchoring.call(kind: "on_demand")
    end

    it "holds: roots recomputed from the entries, links, contiguous ranges" do
      result = Ledger::AnchorChain.verify(entity)

      expect(result).to be_intact
      expect(result.count).to eq(3)
    end

    it "names the anchor whose root no longer follows from the entries (an entry changed directly in the database)" do
      tamper(:accounting_journal_entries) { Accounting::JournalEntry.where(posted_seq: 3).update_all(content_hash: "f" * 64) }

      result = Ledger::AnchorChain.verify(entity)

      expect(result).not_to be_intact
      expect(result.broken_number).to eq(2)
      expect(result.reason).to match(/root/i)
    end

    it "names the anchor whose recorded values were changed, the one whose link was cut, and a range with a hole" do
      tamper(:ledger_anchors) { described_class.where(number: 2).update_all(merkle_root: "e" * 64) }
      expect(Ledger::AnchorChain.verify(entity).broken_number).to eq(2)
    end

    it "sees an anchor taken out of the chain" do
      tamper(:ledger_anchors) { described_class.where(number: 2).delete_all }

      result = Ledger::AnchorChain.verify(entity)

      expect(result).not_to be_intact
      expect(result.broken_number).to eq(3)
    end

    it "sees an entry validated inside the range of an anchor, after it (a range that does not hold the entries it names)" do
      tamper(:ledger_anchors) { described_class.where(number: 1).update_all(entries_count: 5) }

      expect(Ledger::AnchorChain.verify(entity).broken_number).to eq(1)
    end
  end

  describe "what the database allows" do
    it "refuses to change or remove an anchor, but takes the timestamp, once" do
      post_entry
      anchor = Ledger::Anchoring.call(kind: "nightly")

      refuses = ->(message, &block) { expect { ApplicationRecord.transaction(requires_new: true, &block) }.to raise_error(ActiveRecord::StatementInvalid, message) }
      refuses.call(/cannot be changed/) { anchor.update_columns(merkle_root: "0" * 64) }
      refuses.call(/cannot be changed/) { anchor.update_columns(number: 9) }
      refuses.call(/cannot be deleted/) { anchor.delete }
      anchor.update_columns(timestamp_token: "TOKEN", timestamp_authority: "tsa.test", timestamped_at: Time.current)
      expect(anchor.reload.timestamp_token).to eq("TOKEN")
      refuses.call(/timestamp/) { anchor.update_columns(timestamp_token: "OTHER") }
    end
  end
end
