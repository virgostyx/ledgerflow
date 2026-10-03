require "rails_helper"

# F01: migration (F05) and closing (F10) must write into locked periods. They do it only inside a window an owner opened:
# limited in time, with a reason, one at a time, and every use leaves a trace. Nothing else lifts the lock.
RSpec.describe "The controlled window" do
  include_context "with_open_fiscal_year"

  let(:conn)       { ApplicationRecord.connection }
  let(:owner)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let!(:owner_membership)      { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  let(:day)   { fiscal_year.start_date + 14 }
  let(:entry) do
    create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: day).tap do |e|
      Accounting::PostJournalEntry.call(entry: e).tap { |r| raise r.message if r.failure? }
    end
  end

  def lock_month! = create(:period_lock, starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date.end_of_month)
  def open_window(user: owner, **over) = Accounting::OpenControlledWindow.call(user: user, reason: "Opening balances import", purpose: "migration", hours: 2, **over)
  def audit(action) = Accounting::AuditLog.where(action: action)

  describe Accounting::OpenControlledWindow do
    it "opens a window for the owner, with its reason and end, and audits it" do
      result = open_window

      expect(result).to be_success
      window = result[:window]
      expect(window).to have_attributes(opened_by: owner, purpose: "migration", reason: "Opening balances import")
      expect(window.expires_at).to be_within(1.minute).of(2.hours.from_now)
      expect(audit("controlled_window_opened").sole.payload).to include("purpose" => "migration", "reason" => "Opening balances import")
    end

    it "is refused to anyone but an owner" do
      expect(open_window(user: accountant)).to be_failure
      expect(Accounting::ControlledWindow.count).to eq(0)
    end

    it "needs a reason, a known purpose, and 1 to 8 hours" do
      expect(open_window(reason: " ")).to be_failure
      expect(open_window(purpose: "whatever")).to be_failure
      expect(open_window(hours: 0)).to be_failure
      expect(open_window(hours: 9)).to be_failure
      expect(Accounting::ControlledWindow.count).to eq(0)
    end

    it "does not open a second one while one is open" do
      open_window

      expect(open_window).to be_failure
      expect(Accounting::ControlledWindow.count).to eq(1)
    end
  end

  describe Accounting::CloseControlledWindow do
    it "closes it, says who, and audits it" do
      window = open_window[:window]

      expect(described_class.call(window: window, user: owner)).to be_success

      expect(window.reload.closed_at).to be_present
      expect(window.closed_by).to eq(owner)
      expect(audit("controlled_window_closed").count).to eq(1)
      expect(Accounting::ControlledWindow.open_now).to be_empty
    end

    it "is refused to anyone but an owner" do
      window = open_window[:window]

      expect(described_class.call(window: window, user: accountant)).to be_failure
      expect(window.reload.closed_at).to be_nil
    end
  end

  describe ".within" do
    before { entry; lock_month! }

    def change_locked_entry = conn.execute("UPDATE accounting_journal_entries SET description = 'corrected' WHERE id = #{entry.id}")

    it "refuses to run without an open window, and the lock still holds" do
      expect { Accounting::ControlledWindow.within(purpose: "migration") { change_locked_entry } }.to raise_error(Accounting::ControlledWindow::Closed)
      expect { change_locked_entry }.to raise_error(ActiveRecord::StatementInvalid, /locked period/)
    end

    it "lets the block write into the locked period, and only the block" do
      open_window

      Accounting::ControlledWindow.within(purpose: "migration") { change_locked_entry }

      expect(entry.reload.description).to eq("corrected")
      expect { conn.execute("UPDATE accounting_journal_entries SET description = 'after' WHERE id = #{entry.id}") }.to raise_error(ActiveRecord::StatementInvalid, /locked period/)
    end

    it "keeps the lock back on when the block fails" do
      open_window

      expect { Accounting::ControlledWindow.within(purpose: "migration") { raise "boom" } }.to raise_error("boom")
      expect { change_locked_entry }.to raise_error(ActiveRecord::StatementInvalid, /locked period/)
    end

    it "is for the purpose it was opened for" do
      open_window

      expect { Accounting::ControlledWindow.within(purpose: "closing") { change_locked_entry } }.to raise_error(Accounting::ControlledWindow::Closed)
    end

    it "refuses once the window has expired or been closed" do
      window = open_window[:window]
      window.update_columns(expires_at: 1.minute.ago)
      expect { Accounting::ControlledWindow.within(purpose: "migration") { change_locked_entry } }.to raise_error(Accounting::ControlledWindow::Closed)

      window.update_columns(expires_at: 1.hour.from_now, closed_at: Time.current)
      expect { Accounting::ControlledWindow.within(purpose: "migration") { change_locked_entry } }.to raise_error(Accounting::ControlledWindow::Closed)
    end

    it "records each use with its purpose, naming the window" do
      window = open_window[:window]

      Accounting::ControlledWindow.within(purpose: "migration") { change_locked_entry }

      expect(audit("controlled_window_used").sole.payload).to include("purpose" => "migration", "window_id" => window.id)
    end

    it "is bound to the entity: another entity's window does not open this one's lock" do
      other = create(:entity)
      ActsAsTenant.with_tenant(other) do
        create(:user_entity, :admin, user: owner, entity: other)
        Accounting::OpenControlledWindow.call(user: owner, reason: "x", purpose: "migration", hours: 1)
      end

      expect { Accounting::ControlledWindow.within(purpose: "migration") { change_locked_entry } }.to raise_error(Accounting::ControlledWindow::Closed)
    end
  end
end
