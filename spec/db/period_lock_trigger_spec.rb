require "rails_helper"

# F01 second layer: PostgreSQL itself refuses to change the validated entries of a locked period,
# whatever the application code does (raw SQL, update_all, a forgotten guard).
RSpec.describe "Period lock trigger", type: :model do
  include_context "with_open_fiscal_year"

  let(:conn)  { ApplicationRecord.connection }
  let(:day)   { fiscal_year.start_date + 14 }
  let(:entry) do
    create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: day).tap do |e|
      Accounting::PostJournalEntry.call(entry: e).tap { |r| raise r.message if r.failure? }
    end
  end
  let(:line) { entry.lines.first }

  def lock_month!
    create(:period_lock, starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date.end_of_month)
  end

  def refused(&block) = expect(&block).to raise_error(ActiveRecord::StatementInvalid, /locked period/)

  context "once the period is locked" do
    before { entry; lock_month! }

    it "refuses to change an amount of a validated line" do
      refused { conn.execute("UPDATE accounting_journal_entry_lines SET debit = debit + 1, credit = credit WHERE id = #{line.id}") }
    end

    it "refuses to delete a validated line" do
      refused { conn.execute("DELETE FROM accounting_journal_entry_lines WHERE id = #{line.id}") }
    end

    it "refuses to add a line to a validated entry" do
      attrs = line.attributes.except("id")
      refused { Accounting::JournalEntryLine.insert_all([ attrs ]) }
    end

    it "refuses to change a validated entry" do
      refused { conn.execute("UPDATE accounting_journal_entries SET description = 'x' WHERE id = #{entry.id}") }
    end

    it "refuses to delete a validated entry" do
      refused { conn.execute("DELETE FROM accounting_journal_entries WHERE id = #{entry.id}") }
    end

    it "still lets a line be lettered or its residual change" do
      expect { conn.execute("UPDATE accounting_journal_entry_lines SET amount_residual = 0 WHERE id = #{line.id}") }.not_to raise_error
    end

    it "refuses to post a draft dated inside the period, even by raw SQL" do
      draft = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: day)

      refused { conn.execute("UPDATE accounting_journal_entries SET status = 1 WHERE id = #{draft.id}") }
    end

    it "leaves drafts of the period editable and deletable" do
      draft = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: day)

      expect { conn.execute("UPDATE accounting_journal_entries SET description = 'x' WHERE id = #{draft.id}") }.not_to raise_error
    end

    it "lets the controlled window through (session variable set by the migration/closing services)" do
      conn.execute("SELECT set_config('ledgerflow.lock_override', 'on', true)")

      expect { conn.execute("UPDATE accounting_journal_entry_lines SET label = 'fixed' WHERE id = #{line.id}") }.not_to raise_error
    ensure
      conn.execute("SELECT set_config('ledgerflow.lock_override', 'off', true)")
    end
  end

  it "does not touch an entry dated the day after the locked period" do
    after = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date.end_of_month + 1)
    Accounting::PostJournalEntry.call(entry: after)
    lock_month!

    expect { conn.execute("UPDATE accounting_journal_entries SET description = 'x' WHERE id = #{after.id}") }.not_to raise_error
  end

  it "does not touch a period that was unlocked" do
    entry
    lock_month!.update!(status: :unlocked)

    expect { conn.execute("UPDATE accounting_journal_entry_lines SET debit = debit WHERE id = #{line.id}") }.not_to raise_error
  end

  it "does not apply the locks of another entity" do
    entry
    other = create(:entity)
    ActsAsTenant.with_tenant(other) { create(:period_lock, starts_on: fiscal_year.start_date, ends_on: fiscal_year.end_date) }

    expect { conn.execute("UPDATE accounting_journal_entry_lines SET label = 'x' WHERE id = #{line.id}") }.not_to raise_error
  end
end
