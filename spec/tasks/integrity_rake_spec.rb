require "rails_helper"
require "rake"

# B03c: the keys and the check from the command line. Nothing of a private key is printed.
RSpec.describe "integrity rake tasks" do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  before(:all) do
    Rake.application.rake_require("tasks/integrity", [ Rails.root.join("lib").to_s ], [])
    Rake::Task.define_task(:environment)
  end

  def run_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    capture_stdout { task.invoke(*args) }
  end

  def capture_stdout
    out = StringIO.new
    previous = $stdout
    $stdout = out
    yield
    out.string
  ensure
    $stdout = previous
  end

  it "makes a key, lists it, rotates, revokes - and prints no secret" do
    out = run_task("integrity:keys:generate")
    key = Ledger::SigningKey.last
    expect(out).to include(key.key_id).and include(key.fingerprint)
    expect(out).not_to include("PRIVATE")

    expect(run_task("integrity:keys:list")).to include(key.key_id, "active")

    run_task("integrity:keys:generate")
    expect(key.reload.status).to eq("retired")

    revoked = Ledger::SigningKey.find_by(status: "active")
    expect(run_task("integrity:keys:revoke", revoked.key_id, "copied")).to include("is revoked")
    expect(revoked.reload.status).to eq("revoked")
    expect { run_task("integrity:keys:revoke", revoked.key_id, "") }.to raise_error(SystemExit)
  end

  describe "integrity:check" do
    let(:journal) { create(:journal, :purchase) }
    let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
    let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

    before do
      entity.update!(features: entity.features.merge("b03c" => true))
      @entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 3, reference: nil)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: @entry, account: expense, debit: 10, credit: 0)
      create(:journal_entry_line, journal_entry: @entry, account: payable, debit: 0, credit: 10)
      Accounting::PostJournalEntry.call!(entry: @entry)
    end

    it "says intact, and exits non-zero naming the entry when something diverges" do
      expect(run_task("integrity:check", "full")).to include("intact (1 entries checked)")

      tamper(:accounting_journal_entry_lines) { @entry.lines.first.update_columns(debit: 11, credit: 0) }
      expect { run_task("integrity:check", "full") }.to raise_error(SystemExit)
    end
  end
end
