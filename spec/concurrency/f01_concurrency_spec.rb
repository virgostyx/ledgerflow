require "rails_helper"

# F01 review: what must hold when two people (or two clicks) act at the same moment.
RSpec.describe "F01 under concurrency", :concurrency do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let(:other) { create(:user) }

  # the factory defers the double-entry check, which needs a transaction (the usual one is rolled back, not here)
  def entry_for(**attrs) = ApplicationRecord.transaction { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, **attrs) }

  def post_entry(entry) = -> { Current.set(user: user) { Accounting::PostJournalEntry.call(entry: Accounting::JournalEntry.find(entry.id)) } }

  it "gives distinct, consecutive numbers to entries validated at the same moment in one journal" do
    journal = create(:journal, :misc, code: "OD")
    entries = Array.new(4) { entry_for(journal: journal, reference: nil) }

    results = concurrently(*entries.map { |e| post_entry(e) }, entity: entity)

    expect(results).to all(be_success)
    references = entries.map { |e| e.reload.reference }
    expect(references.uniq.size).to eq(4)
    expect(references.map { |r| r[/\d+\z/].to_i }.sort).to eq((1..4).to_a)
  end

  it "validates a double-clicked entry once: one success, one refusal, one audit row" do
    entry = entry_for

    results = concurrently(post_entry(entry), post_entry(entry), entity: entity)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(Accounting::AuditLog.where(action: "post_entry", auditable_id: entry.id).count).to eq(1)
  end

  it "unlocks a period once when two owners click at the same moment: one success, one refusal, one audit row, one mail" do
    lock = create(:period_lock)
    create(:user_entity, :admin, entity: entity)
    unlock = ->(who) { -> { Accounting::UnlockPeriod.call(lock: Accounting::PeriodLock.find(lock.id), user: who, reason: "needed") } }

    results = nil
    expect { results = concurrently(unlock.(user), unlock.(other), entity: entity) }.to have_enqueued_mail(Accounting::PeriodMailer, :unlocked).once

    expect(results.count(&:success?)).to eq(1)
    expect(Accounting::AuditLog.where(action: "unlock_period", auditable_id: lock.id).count).to eq(1)
  end

  it "locks the same month once when two accountants click at the same moment" do
    month = [ fiscal_year.start_date.strftime("%Y-%m") ]
    lock = -> { Accounting::LockMonths.call(months: month, user: user) }

    concurrently(lock, lock, entity: entity)

    expect(Accounting::PeriodLock.locked.count).to eq(1)
    expect(Accounting::AuditLog.where(action: "lock_period").count).to eq(1)
  end

  it "refuses to lock a range that is already locked for the same kind, however the second request arrives" do
    range = { starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date.end_of_month, user: user }
    lock = -> { Accounting::LockPeriod.call(**range) }

    results = concurrently(lock, lock, entity: entity)

    expect(results.count(&:success?)).to eq(1)
    expect(Accounting::PeriodLock.locked.count).to eq(1)
  end

  it "opens a single controlled window when two owners ask at the same moment" do
    create(:user_entity, :admin, user: user, entity: entity)
    create(:user_entity, :admin, user: other, entity: entity)
    open = ->(who) { -> { Accounting::OpenControlledWindow.call(user: who, reason: "import", purpose: "migration", hours: 1) } }

    results = concurrently(open.(user), open.(other), entity: entity)

    expect(results.count(&:success?)).to eq(1)
    expect(Accounting::ControlledWindow.open_now.count).to eq(1)
  end

  it "keeps the audit chain of the entity intact when many things are written at once" do
    entries = Array.new(4) { entry_for }

    concurrently(*entries.map { |e| post_entry(e) }, entity: entity)

    verdict = Accounting::AuditVerifier.call(entity: entity)

    expect(verdict).to be_intact
    expect(verdict.count).to be >= 4
  end
end
