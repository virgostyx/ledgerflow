require "rails_helper"

# B03a §7 "Ce qui rend la reconstruction fiable" (1 and 2): a validated entry carries the instant of its validation and its place in the order of the
# company, both fixed by the database, never changed.
RSpec.describe "The order in which entries are validated" do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }

  let(:journal) { create(:journal, :misc, code: "OD") }

  def draft(**attrs) = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, journal: journal, reference: nil, **attrs)

  def post(entry)
    result = Current.set(user: user) { Accounting::PostJournalEntry.call(entry: entry) }
    raise result.message if result.failure?

    entry.reload
  end

  def db_now = ApplicationRecord.connection.select_value("SELECT clock_timestamp() AT TIME ZONE 'UTC'").then { |t| t.is_a?(String) ? Time.utc(*t.scan(/\d+/).map(&:to_i)) : t }

  it "leaves a draft without an instant or a place" do
    entry = draft

    expect([ entry.posted_at, entry.posted_seq, entry.posted_at_source ]).to all(be_nil)
  end

  it "gives the instant (from the database clock) and the next number of the company when the entry is validated" do
    before = db_now
    first = post(draft)
    second = post(draft)
    after = db_now

    expect(first.posted_seq).to eq(1)
    expect(second.posted_seq).to eq(2)
    expect(first.posted_at).to be_between(before - 0.001, after + 0.001)
    expect(second.posted_at).to be >= first.posted_at
    expect(first.posted_at_source).to eq("live")
  end

  it "takes the instant from the database, not from the application clock" do
    entry = nil
    travel_to(Time.zone.local(2031, 1, 1)) { entry = post(draft) }

    expect(entry.posted_at).to be < Time.zone.local(2030, 1, 1)
  end

  it "numbers each company on its own" do
    other = create(:entity)
    post(draft)
    foreign = ActsAsTenant.with_tenant(other) do
      create(:journal_entry, :posted, entity: other, fiscal_year: create(:fiscal_year, entity: other), journal: create(:journal, entity: other), reference: "X-1")
    end

    expect(foreign.reload.posted_seq).to eq(1)
  end

  it "gives an entry written as validated from the start (a reversal, an import) its place too" do
    entry = create(:journal_entry, :posted, fiscal_year: fiscal_year, reference: "P-1")

    expect(entry.reload.posted_seq).to eq(1)
    expect(entry.posted_at).to be_present
  end

  it "marks an entry that came with an import as such" do
    batch = Accounting::ImportBatch.create!(parser: "coda", file_sha256: "posting-order", result: "imported")
    entry = create(:journal_entry, :posted, fiscal_year: fiscal_year, reference: "P-2", import_batch_id: batch.id)

    expect(entry.reload.posted_at_source).to eq("import")
  end

  it "gives one instant to the entries validated in one transaction, and distinct places in the order" do
    entries = ApplicationRecord.transaction { Array.new(3) { draft } }
    ApplicationRecord.transaction { entries.each { |e| Current.set(user: user) { Accounting::PostJournalEntry.call(entry: e).tap { |r| raise r.message if r.failure? } } } }
    entries.each(&:reload)

    expect(entries.map(&:posted_seq)).to eq([ 1, 2, 3 ])
    expect(entries.map(&:posted_at).uniq.size).to eq(1)
  end

  it "keeps the place of an entry once it is reversed, and gives the reversal its own" do
    original = post(draft)
    reversal = Accounting::ReverseJournalEntry.call(entry: original, reason: "mistake", user: user)[:reversal]

    expect(original.reload).to be_reversed
    expect(original.posted_seq).to eq(1)
    expect(reversal.reload.posted_seq).to eq(2)
    expect(reversal.posted_at).to be >= original.posted_at
  end

  describe "what the database refuses" do
    let!(:entry) { post(draft) }

    def refuses(&block) = expect { ApplicationRecord.transaction(requires_new: true, &block) }.to raise_error(ActiveRecord::StatementInvalid, /posted/i)

    it "changing the instant, the place or the source of a validated entry" do
      refuses { entry.update_columns(posted_at: 1.year.ago) }
      refuses { entry.update_columns(posted_seq: 99) }
      refuses { entry.update_columns(posted_at_source: "import") }
    end

    it "changing them even in the window that lifts the period locks" do
      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute("SET LOCAL ledgerflow.lock_override = 'on'")
        refuses { entry.update_columns(posted_at: 1.year.ago) }
      end
    end

    it "putting an instant on a draft, or sending an entry back to a draft with its place" do
      pending_entry = draft

      refuses { pending_entry.update_columns(posted_at: Time.current) }
      refuses { entry.update_columns(status: Accounting::JournalEntry.statuses[:draft]) }
    end
  end
end
