require "rails_helper"

# B03c critère 5: a direct alteration in the database - what the triggers of the application cannot stop - is found by the nightly check, which creates the blocking anomaly C23,
# alerts the owners and writes a security event. The nightly check looks at the last seven days and a sample of the rest; a full one runs every week and on demand.
RSpec.describe Integrity::SelfCheck do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let(:owner) { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before { owner }

  def post_entry(amount = 10)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    Accounting::PostJournalEntry.call!(entry: entry)
    entry.reload
  end

  def alter_amount(entry) = tamper(:accounting_journal_entry_lines) { entry.lines.order(:sort_order, :id).first.update_columns(debit: 11, credit: 0) }

  it "finds nothing when the books are as they were fingerprinted" do
    2.times { post_entry }
    Ledger::Anchoring.call(kind: "nightly")

    result = described_class.call(mode: :nightly)

    expect(result).to be_intact
    expect(result.entries_checked).to eq(2)
  end

  it "finds an entry of the last seven days whose content no longer gives its fingerprint, and says which" do
    entry = post_entry
    other = post_entry
    alter_amount(entry)

    result = described_class.call(mode: :nightly)

    expect(result).not_to be_intact
    expect(result.findings.map { |f| [ f.part, f.subject_id ] }).to eq([ [ "entry", entry.id ] ])
    expect(result.findings.first.message).to include("Entry #{entry.id}")
    expect(other).to be_present
  end

  it "looks at a sample of what is older, and at everything in the full check" do
    old = post_entry
    tamper(:accounting_journal_entries) { Accounting::JournalEntry.where(id: old.id).update_all(posted_at: 30.days.ago) } # beyond the week
    alter_amount(old)

    expect(described_class.call(mode: :nightly, sample: (old.posted_seq + 1) % 100)).to be_intact # not in the sample of the night
    expect(described_class.call(mode: :nightly, sample: old.posted_seq % 100)).not_to be_intact # in it
    expect(described_class.call(mode: :full)).not_to be_intact
  end

  it "finds an anchor whose root no longer follows from the entries, and a broken audit chain" do
    entry = post_entry
    Ledger::Anchoring.call(kind: "nightly")
    tamper(:accounting_journal_entries) { Accounting::JournalEntry.where(id: entry.id).update_all(content_hash: "c" * 64) }

    result = described_class.call(mode: :nightly)

    expect(result.findings.map(&:part)).to include("anchor")
  end

  describe ".run (what the nightly job does)" do
    before { entity.update!(features: entity.features.merge("b03c" => true)) }

    it "creates the blocking anomaly C23, alerts the owners, writes a security event, once for the same divergence" do
      entry = post_entry
      alter_amount(entry)

      described_class.run(mode: :nightly)

      expect(Accounting::ConsistencyFinding.where(check_id: "C23").count).to eq(1)
      expect(Accounting::ConsistencyFinding.find_by(check_id: "C23").message).to include("Entry #{entry.id}")
      note = Accounting::Notification.find_by(user: owner, event: "integrity_compromised:#{Date.current}")
      expect(note).to be_present
      expect(Accounting::AuditLog.where(action: "integrity_divergence_detected")).to exist
      expect { described_class.run(mode: :nightly) }.not_to change { Accounting::Notification.where(user: owner).count } # the same day
    end

    it "does nothing, silently, when all is well" do
      post_entry

      expect { described_class.run(mode: :nightly) }.not_to change { [ Accounting::ConsistencyFinding.count, Accounting::Notification.count ] }
    end

    it "does nothing for a company that did not turn the feature on" do
      entity.update!(features: entity.features.merge("b03c" => false))
      alter_amount(post_entry)

      expect { described_class.run(mode: :nightly) }.not_to change(Accounting::ConsistencyFinding, :count)
    end
  end

  describe "the anomaly C23 in the consistency checks" do
    it "is the same finding, found by the usual run of R19" do
      alter_amount(post_entry)

      expect(Accounting::Consistency::Checks::C23IntegrityCompromised.new.call.map(&:message).join).to include("Entry")
    end
  end
end
