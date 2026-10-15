require "rails_helper"

# B03c: every night each company that turned the feature on gets the anchor of the day; the first one covers the history that predates the fingerprints, and says so.
RSpec.describe Ledger::NightlyAnchoring do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  def post_entry
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: 10, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: 10)
    Accounting::PostJournalEntry.call!(entry: entry)
    entry.reload
  end

  def turn_on(value) = entity.update!(features: entity.features.merge("b03c" => value))

  it "does nothing for a company that did not turn the feature on" do
    turn_on(false)
    post_entry

    expect { described_class.call }.not_to change(Ledger::Anchor, :count)
  end

  it "makes the nightly anchor of each company that did" do
    turn_on(true)
    post_entry

    expect { described_class.call }.to change { ActsAsTenant.with_tenant(entity) { Ledger::Anchor.where(kind: "nightly").count } }.by(1)
  end

  it "starts with the retroactive anchor when the entries predate the fingerprints, then goes on nightly" do
    turn_on(true)
    entry = post_entry
    tamper(:accounting_journal_entries) { Accounting::JournalEntry.where(id: entry.id).update_all(content_hash: nil, content_hash_source: nil) }

    described_class.call
    post_entry
    described_class.call

    expect(ActsAsTenant.with_tenant(entity) { Ledger::Anchor.chronological.pluck(:kind, :retroactive_entries) }).to eq([ [ "retroactive", 1 ], [ "nightly", 0 ] ])
  end

  it "goes on for the other companies when one is refused, and tells it (a security event of the company)" do
    turn_on(true)
    post_entry
    create(:journal_entry, :posted, fiscal_year: fiscal_year, journal: journal, reference: "BARE-1") # has no line: it cannot be anchored
    other = create(:entity, features: Entity::FEATURES.index_with { true })
    ActsAsTenant.with_tenant(other) do
      oj = create(:journal, :purchase, entity: other)
      of = create(:fiscal_year, entity: other, status: :open)
      ea = create(:account, code: "604000", entity: other, account_type: :expense, normal_balance: :debit, account_class: 6)
      eb = create(:account, code: "440000", entity: other, account_type: :liability, normal_balance: :credit, account_class: 4)
      e = create(:journal_entry, :draft, entity: other, journal: oj, fiscal_year: of, entry_date: of.start_date + 3, reference: nil)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: e, account: ea, debit: 5, credit: 0, entity: other)
      create(:journal_entry_line, journal_entry: e, account: eb, debit: 0, credit: 5, entity: other)
      Accounting::PostJournalEntry.call!(entry: e)
    end

    described_class.call

    expect(ActsAsTenant.with_tenant(other) { Ledger::Anchor.count }).to eq(1)
    expect(ActsAsTenant.with_tenant(entity) { Ledger::Anchor.count }).to eq(0)
    expect(Accounting::AuditLog.unscoped.where(entity_id: entity.id, action: "anchoring_refused")).to exist
  end
end
