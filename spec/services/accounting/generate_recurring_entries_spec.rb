require "rails_helper"

# F07 §10, recurring entries: idempotent generation, catch-up (12 at most), blocked by a locked period or an archived account, indexation,
# the post mode that only an owner may allow, the end of a schedule, concurrent runs.
RSpec.describe Accounting::GenerateRecurringEntries do
  include_context "with_pcmn_accounts"

  # a fiscal year that spans two calendar years: July 2026 to June 2027
  let!(:fiscal_year) { create(:fiscal_year, year: 2026, start_date: Date.new(2026, 7, 1), end_date: Date.new(2027, 6, 30), status: :open, entity: entity) }
  let!(:misc)  { create(:journal, journal_type: :misc) }
  let(:owner)  { create(:user, role: :admin) }
  let!(:owner_membership) { create(:user_entity, :admin, user: owner, entity: entity) }
  let(:template) do
    Accounting::EntryTemplate.new(name: "Rent", journal: misc, description: "Rent {mois} {année}").tap do |t|
      t.lines.build(account: account_604, side: :debit, amount_kind: :percent, percentage: 100, label: "Rent", position: 0)
      t.lines.build(account: account_440, side: :credit, amount_kind: :percent, percentage: 100, label: "Landlord", position: 1)
      t.save!
    end
  end

  def recurring(**attrs)
    Accounting::RecurringEntry.create!({ name: "Office rent", entry_template: template, frequency: :monthly, day_of_month: 1, starts_on: Date.new(2026, 8, 1),
                                         base_amount: BigDecimal("1000"), created_by: owner }.merge(attrs))
  end

  def entries(rec) = Accounting::RecurringRun.where(recurring_entry_id: rec.id).where.not(journal_entry_id: nil).order(:due_on).map(&:journal_entry)

  describe "idempotence (criterion 1)" do
    it "makes one entry per due date, however many times it runs the same day" do
      rec = recurring
      3.times { travel_to(Date.new(2026, 8, 1)) { described_class.call } }

      expect(entries(rec).map(&:entry_date)).to eq([ Date.new(2026, 8, 1) ])
      expect(Accounting::RecurringRun.where(recurring_entry_id: rec.id).count).to eq(1)
    end

    it "makes the draft the template says, at the due date" do
      rec = recurring
      travel_to(Date.new(2026, 8, 1)) { described_class.call }

      entry = entries(rec).sole
      expect(entry).to be_draft
      expect(entry.lines.map { |l| [ l.account_id, l.debit, l.credit ] }).to match_array([ [ account_604.id, 1000, 0 ], [ account_440.id, 0, 1000 ] ])
      expect(entry.description).to eq("Rent August 2026")
    end

    it "does nothing before the due date" do
      rec = recurring
      travel_to(Date.new(2026, 7, 31)) { described_class.call }

      expect(entries(rec)).to be_empty
    end

    it "moves on to the next due date" do
      rec = recurring
      travel_to(Date.new(2026, 8, 1)) { described_class.call }

      expect(rec.reload).to have_attributes(next_due_on: Date.new(2026, 9, 1), occurrences_count: 1)
    end
  end

  describe "catch-up (criterion 2)" do
    it "makes up three missed months as drafts, with their own dates" do
      rec = recurring(starts_on: Date.new(2026, 8, 1))
      travel_to(Date.new(2026, 8, 1)) { described_class.call }
      travel_to(Date.new(2026, 11, 1)) { described_class.call }

      expect(entries(rec).map(&:entry_date)).to eq([ Date.new(2026, 8, 1), Date.new(2026, 9, 1), Date.new(2026, 10, 1), Date.new(2026, 11, 1) ])
      expect(entries(rec)).to all(be_draft)
    end

    it "makes up 12 at most in one run, and tells the owners about the rest" do
      fiscal_year.update!(start_date: Date.new(2025, 1, 1), end_date: Date.new(2027, 12, 31))
      rec = recurring(starts_on: Date.new(2025, 1, 1))

      expect { travel_to(Date.new(2027, 6, 1)) { described_class.call } }.to have_enqueued_mail(Accounting::RecurringMailer, :backlog)

      expect(entries(rec).size).to eq(12)
      expect(rec.reload.next_due_on).to eq(Date.new(2026, 1, 1))
    end
  end

  describe "a locked period (criterion 3)" do
    it "generates nothing, blocks the schedule with the reason, and tells the owners" do
      rec = recurring
      create(:period_lock, starts_on: Date.new(2026, 8, 1), ends_on: Date.new(2026, 8, 31))

      expect { travel_to(Date.new(2026, 8, 1)) { described_class.call } }.to have_enqueued_mail(Accounting::RecurringMailer, :blocked)

      expect(entries(rec)).to be_empty
      expect(Accounting::JournalEntry.count).to eq(0)
      expect(rec.reload).to have_attributes(status: "blocked")
      expect(rec.blocked_reason).to include("locked")
    end

    it "does not tell the owners again at every run" do
      recurring
      create(:period_lock, starts_on: Date.new(2026, 8, 1), ends_on: Date.new(2026, 8, 31))
      travel_to(Date.new(2026, 8, 1)) { described_class.call }

      expect { travel_to(Date.new(2026, 8, 2)) { described_class.call } }.not_to have_enqueued_mail(Accounting::RecurringMailer, :blocked)
    end

    it "carries on by itself once the period is unlocked" do
      rec = recurring
      lock = create(:period_lock, starts_on: Date.new(2026, 8, 1), ends_on: Date.new(2026, 8, 31))
      travel_to(Date.new(2026, 8, 1)) { described_class.call }
      lock.update!(status: :unlocked)
      travel_to(Date.new(2026, 8, 2)) { described_class.call }

      expect(entries(rec).map(&:entry_date)).to eq([ Date.new(2026, 8, 1) ])
      expect(rec.reload).to have_attributes(status: "active", blocked_reason: nil)
    end
  end

  describe "an account that cannot be used" do
    it "blocks with the reason, naming the account" do
      rec = recurring
      account_604.update!(active: false)
      travel_to(Date.new(2026, 8, 1)) { described_class.call }

      expect(rec.reload).to have_attributes(status: "blocked")
      expect(rec.blocked_reason).to include("604000")
      expect(Accounting::RecurringRun.sole).to have_attributes(status: "blocked")
    end
  end

  describe "indexation (criterion 4)" do
    it "raises the amount by the percentage on the first occurrence of the year after the first, and keeps the old and new amounts" do
      rec = recurring(indexation_percent: BigDecimal("3"))
      travel_to(Date.new(2026, 12, 1)) { described_class.call }
      expect(entries(rec).last.lines.find_by(account: account_604).debit).to eq(BigDecimal("1000"))

      travel_to(Date.new(2027, 1, 1)) { described_class.call }

      expect(entries(rec).last.lines.find_by(account: account_604).debit).to eq(BigDecimal("1030.00"))
      expect(rec.reload.base_amount).to eq(BigDecimal("1030.00"))
      log = Accounting::AuditLog.where(auditable_type: "Accounting::RecurringEntry", auditable_id: rec.id, action: "recurring_indexed").sole
      expect(log.payload).to include("old_amount" => "1000.0", "new_amount" => "1030.0", "percent" => "3.0")
    end

    it "does it once a year only" do
      rec = recurring(indexation_percent: 3)
      travel_to(Date.new(2027, 2, 1)) { described_class.call }

      expect(rec.reload.base_amount).to eq(BigDecimal("1030.00"))
    end
  end

  describe "the post mode (criterion 8)" do
    it "is refused until an owner has approved it" do
      expect { recurring(mode: :post) }.to raise_error(ActiveRecord::RecordInvalid, /approved/)
    end

    it "posts by itself once approved by an owner" do
      rec = recurring
      Accounting::ApproveRecurringPost.call(recurring: rec, user: owner)
      travel_to(Date.new(2026, 8, 1)) { described_class.call }

      expect(entries(rec).sole).to be_posted
    end

    it "is not for an accountant to allow" do
      accountant = create(:user, role: :accountant)
      create(:user_entity, :accountant, user: accountant, entity: entity)

      expect(Accounting::ApproveRecurringPost.call(recurring: recurring, user: accountant)).to be_failure
    end

    it "falls back to drafts when the amount or the template is changed after the approval" do
      rec = recurring
      Accounting::ApproveRecurringPost.call(recurring: rec, user: owner)

      rec.reload.update!(base_amount: 1200)

      expect(rec.reload).to have_attributes(mode: "draft", post_approved_by_id: nil)
    end
  end

  describe "the schedule" do
    it "uses the last day of a short month for a 31st" do
      rec = recurring(day_of_month: 31, starts_on: Date.new(2026, 7, 31))
      travel_to(Date.new(2027, 2, 28)) { described_class.call }

      expect(entries(rec).map(&:entry_date)).to include(Date.new(2026, 11, 30), Date.new(2027, 2, 28))
    end

    it "uses the last day of every month when no day is given" do
      rec = recurring(day_of_month: nil, starts_on: Date.new(2026, 8, 1))
      travel_to(Date.new(2026, 9, 30)) { described_class.call }

      expect(entries(rec).map(&:entry_date)).to eq([ Date.new(2026, 8, 31), Date.new(2026, 9, 30) ])
    end

    it "runs quarterly and yearly" do
      quarterly = recurring(name: "Q", frequency: :quarterly)
      travel_to(Date.new(2027, 2, 1)) { described_class.call }

      expect(entries(quarterly).map(&:entry_date)).to eq([ Date.new(2026, 8, 1), Date.new(2026, 11, 1), Date.new(2027, 2, 1) ])
    end

    it "ends after the maximum number of occurrences, or the end date" do
      by_count = recurring(name: "A", max_occurrences: 2)
      by_date  = recurring(name: "B", ends_on: Date.new(2026, 9, 15))
      travel_to(Date.new(2026, 12, 1)) { described_class.call }

      expect(entries(by_count).size).to eq(2)
      expect(entries(by_date).size).to eq(2)
      expect([ by_count, by_date ].map { |r| r.reload.status }).to eq(%w[finished finished])
    end

    it "does not run while paused" do
      rec = recurring
      rec.paused!
      travel_to(Date.new(2026, 8, 1)) { described_class.call }

      expect(entries(rec)).to be_empty
    end

    it "makes the entry ahead of the due date by the lead days, dated at the due date" do
      rec = recurring(lead_days: 5)
      travel_to(Date.new(2026, 7, 27)) { described_class.call }

      expect(entries(rec).map(&:entry_date)).to eq([ Date.new(2026, 8, 1) ])
    end
  end

  describe "deleting a recurring entry that has run" do
    it "keeps the entries and where they came from" do
      rec = recurring
      travel_to(Date.new(2026, 8, 1)) { described_class.call }
      entry_id = Accounting::RecurringRun.sole.journal_entry_id

      rec.destroy!

      expect(Accounting::JournalEntry.exists?(entry_id)).to be(true)
      expect(Accounting::RecurringRun.sole).to have_attributes(journal_entry_id: entry_id, recurring_name: "Office rent", recurring_entry_id: nil)
    end
  end

  describe "two runs at the same moment", :concurrency do
    it "makes one entry per due date" do
      rec = recurring
      travel_to(Date.new(2026, 8, 1)) do
        concurrently(-> { described_class.call }, -> { described_class.call }, entity: entity)
      end

      expect(Accounting::RecurringRun.where(recurring_entry_id: rec.id).count).to eq(1)
      expect(Accounting::JournalEntry.count).to eq(1)
    end
  end
end
