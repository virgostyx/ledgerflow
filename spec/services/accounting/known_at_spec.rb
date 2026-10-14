require "rails_helper"

# B03a: what an instant means for the books of a company: the last place validated at that instant, the view of today, or a refusal before the history is guaranteed.
RSpec.describe Accounting::KnownAt do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :misc, code: "OD") }

  def post_entry
    entry = create(:journal_entry, :posted, fiscal_year: fiscal_year, journal: journal, reference: "K-#{SecureRandom.hex(3)}")
    next_posting_instant # the clock of the database is read at validation: leave room between two of them
    entry.reload
  end

  it "is today's view when there is no instant, or one that is now or later" do
    now = Time.current

    expect(described_class.new(nil)).to be_current
    travel_to(now) { expect(described_class.new(now)).to be_current }
    expect(described_class.new(1.day.from_now)).to be_current
  end

  it "stops at the last place validated at or before the instant" do
    first = post_entry
    middle = first.posted_at + 0.005
    second = post_entry

    expect(described_class.new(first.posted_at).seq).to eq(first.posted_seq)
    expect(described_class.new(middle).seq).to eq(first.posted_seq)
    expect(described_class.new(second.posted_at).seq).to eq(second.posted_seq)
  end

  it "has no place before the first validation" do
    Accounting::HistoryStart.create!(starts_at: 1.day.ago)
    first = post_entry

    expect(described_class.new(first.posted_at - 1)).not_to be_refused
    expect(described_class.new(first.posted_at - 1).seq).to eq(0)
  end

  describe "the start of the history" do
    it "refuses an instant before the start of the history of the company, and says from when it is guaranteed" do
      first = post_entry
      Accounting::HistoryStart.create!(starts_at: first.posted_at - 1.hour)

      known = described_class.new(first.posted_at - 2.hours)

      expect(known).to be_refused
      expect(known.refusal).to match(/history/i)
      expect(known.history_start).to eq(first.posted_at - 1.hour)
      expect(described_class.new(first.posted_at - 30.minutes)).not_to be_refused
    end

    it "takes the start of the fiscal year asked for before the one of the company" do
      Accounting::HistoryStart.create!(starts_at: 10.days.ago)
      Accounting::HistoryStart.create!(starts_at: 2.days.ago, fiscal_year: fiscal_year)

      expect(described_class.new(5.days.ago, fiscal_year: fiscal_year)).to be_refused
      expect(described_class.new(5.days.ago)).not_to be_refused
    end

    it "starts, for a company without any row, when the company was created" do
      expect(described_class.new(entity.created_at - 1.day)).to be_refused
      expect(described_class.new(entity.created_at + 1.second, fiscal_year: fiscal_year)).not_to be_refused
    end

    it "keeps one row per company and fiscal year" do
      Accounting::HistoryStart.create!(starts_at: 1.day.ago)

      expect(Accounting::HistoryStart.new(starts_at: 2.days.ago)).not_to be_valid
    end
  end

  it "reads the places of the company asked for only" do
    post_entry
    other = create(:entity)

    ActsAsTenant.with_tenant(other) do
      expect(described_class.new(Time.current - 1.second).seq).to eq(0)
    end
  end

  describe ".parse" do
    it "reads an instant with its offset exactly" do
      expect(described_class.parse("2026-01-15T09:30:00+01:00")).to eq(Time.utc(2026, 1, 15, 8, 30))
      expect(described_class.parse("2026-01-15T09:30Z")).to eq(Time.utc(2026, 1, 15, 9, 30))
    end

    it "reads a local time as the time of the application" do
      Time.use_zone("Brussels") { expect(described_class.parse("2026-01-15 09:30")).to eq(Time.utc(2026, 1, 15, 8, 30)) }
    end

    it "refuses a local time that exists twice (the clock goes back) or not at all (it goes forward), and asks for the offset" do
      Time.use_zone("Brussels") do
        expect { described_class.parse("2026-10-25T02:30") }.to raise_error(described_class::Invalid, /offset/)
        expect { described_class.parse("2026-03-29T02:30") }.to raise_error(described_class::Invalid, /offset/)
        expect(described_class.parse("2026-10-25T02:30+01:00")).to eq(Time.utc(2026, 10, 25, 1, 30))
      end
    end

    it "refuses what is not an instant" do
      [ "", "yesterday", "2026-13-45T10:00", "15/01/2026" ].each { |text| expect { described_class.parse(text) }.to raise_error(described_class::Invalid) }
    end
  end
end
