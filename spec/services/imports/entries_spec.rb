require "rails_helper"

RSpec.describe "Guided import of entries" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user)  { create(:user, role: :accountant) }
  let!(:journal) { create(:journal, code: "OD", journal_type: :misc) }
  let(:day)   { (fiscal_year.start_date + 20).iso8601 }

  before { create(:user_entity, :accountant, user: user, entity: entity) }

  describe "criteria 1 to 3" do
    # 1 000 lines: 332 pieces of 3 lines and one of 4; three of the pieces do not balance
    let(:pieces) do
      (1..332).map do |i|
        amount = i.to_s
        [ "P#{i}", day, [ [ "604000", amount, "" ], [ "604000", "1.00", "" ], [ "440000", "", (i + 1).to_s ] ] ].tap do |piece|
          piece.last.last[2] = (i + 2).to_s if [ 10, 20, 30 ].include?(i) # unbalanced by 1.00
        end
      end + [ [ "P333", day, [ [ "604000", "1", "" ], [ "604000", "1", "" ], [ "604000", "1", "" ], [ "440000", "", "3" ] ] ] ]
    end
    let(:csv) { entries_csv(pieces) }

    it "creates every valid piece as a draft and lists the three refused ones with their cause (criterion 1)" do
      expect(csv.lines.size - 1).to eq(1000)
      batch = run_import(start_import("entries", csv, user: user), user: user)

      expect(batch.result).to eq("imported")
      expect(Accounting::JournalEntry.where(import_batch_id: batch.id).count).to eq(330)
      expect(Accounting::JournalEntry.where(import_batch_id: batch.id).pluck(:status).uniq).to eq([ "draft" ])
      expect(batch.errors_list.map { |e| e["ref"] }).to match_array(%w[P10 P20 P30])
      expect(batch.errors_list.first["message"]).to match(/does not balance.*debit 11.00.*credit 12.00/i)
      expect(batch.summary).to include("created" => 330, "refused" => 3, "skipped" => 0)
    end

    it "creates nothing more when the same file is run again (criterion 2)" do
      first = run_import(start_import("entries", csv, user: user), user: user)
      expect { run_import(start_import("entries", csv, user: user), user: user) }.not_to change(Accounting::JournalEntry, :count)

      again = Accounting::ImportBatch.order(:id).last
      expect(again.summary).to include("created" => 0, "skipped" => 330, "refused" => 3)
      expect(first.id).not_to eq(again.id)
    end

    it "takes back only its own drafts (criterion 3)" do
      other = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1)
      small = entries_csv([ balanced("A1", day), balanced("A2", day) ])
      other_batch = run_import(start_import("entries", small, user: user), user: user)
      batch = run_import(start_import("entries", entries_csv([ balanced("B1", day), balanced("B2", day), balanced("B3", day) ]), user: user), user: user)

      expect { Imports::Undo.call(batch: batch, user: user) }.to change(Accounting::JournalEntry, :count).by(-3)
      expect(batch.reload.result).to eq("undone")
      expect(Accounting::JournalEntry.where(import_batch_id: other_batch.id).count).to eq(2)
      expect(Accounting::JournalEntry.exists?(other.id)).to be(true)
    end
  end

  it "writes nothing in a simulation, and says what it would do" do
    batch = start_import("entries", entries_csv([ balanced("A1", day), balanced("A2", day) ]), user: user)
    expect { run_import(batch, user: user, dry_run: true) }.not_to change(Accounting::JournalEntry, :count)

    expect(batch.reload.result).to eq("uploaded")
    expect(batch.summary).to include("created" => 2, "simulation" => true)
  end

  it "keeps the piece on the right side of the ledger: debit, credit, label, journal and date" do
    batch = run_import(start_import("entries", entries_csv([ balanced("A1", day, "12.50") ]), user: user), user: user)
    entry = Accounting::JournalEntry.find_by(import_batch_id: batch.id)

    expect(entry).to have_attributes(external_id: "A1", entry_date: Date.parse(day), journal: journal, fiscal_year: fiscal_year, created_by: user)
    expect(entry.lines.order(:id).map { |l| [ l.account.code, l.debit, l.credit, l.label ] })
      .to eq([ [ "604000", BigDecimal("12.5"), 0, "Line A1" ], [ "440000", 0, BigDecimal("12.5"), "Line A1" ] ])
  end

  it "never creates an unknown account: the piece is refused and the value is offered for linking" do
    csv = entries_csv([ [ "A1", day, [ [ "604999", "5", "" ], [ "440000", "", "5" ] ] ], balanced("A2", day) ])
    batch = run_import(start_import("entries", csv, user: user), user: user)

    expect(batch.summary).to include("created" => 1, "refused" => 1)
    expect(batch.errors_list.first["message"]).to include("account 604999 is unknown")
    expect(batch.summary["unknowns"]).to eq("accounts" => [ "604999" ])
    expect(Accounting::Account.where(code: "604999")).to be_empty
  end

  it "accepts the unknown account once it is linked to an existing one" do
    csv = entries_csv([ [ "A1", day, [ [ "604999", "5", "" ], [ "440000", "", "5" ] ] ] ])
    batch = start_import("entries", csv, user: user)
    batch.update!(mapping: batch.mapping.merge("resolutions" => { "accounts" => { "604999" => "604000" } }))

    run_import(batch, user: user)
    expect(Accounting::JournalEntry.find_by(external_id: "A1").lines.map { |l| l.account.code }).to match_array(%w[604000 440000])
  end

  it "refuses dates that do not read in the chosen format, naming the lines, rather than guessing" do
    csv = entries_csv([ balanced("A1", "31/01/2026"), balanced("A2", day), balanced("A3", "2026-13-45") ])
    batch = run_import(start_import("entries", csv, user: user), user: user)

    expect(batch.summary).to include("created" => 1, "refused" => 2)
    expect(batch.errors_list.map { |e| [ e["ref"], e["lines"] ] }).to eq([ [ "A1", [ 2, 3 ] ], [ "A3", [ 6, 7 ] ] ])
    expect(batch.errors_list.first["message"]).to match(/date "31\/01\/2026" is not YYYY-MM-DD/)
  end

  it "reads day-month-year dates when the options say so" do
    csv = entries_csv([ balanced("A1", "05/03/2026") ])
    batch = start_import("entries", csv, user: user, options: { "date_format" => "dmy" })
    fiscal_year.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31))

    run_import(batch, user: user)
    expect(Accounting::JournalEntry.find_by(external_id: "A1").entry_date).to eq(Date.new(2026, 3, 5))
  end

  it "reads decimal commas when the options say so" do
    csv = entries_csv([ [ "A1", day, [ [ "604000", "1.234,50", "" ], [ "440000", "", "1.234,50" ] ] ] ])
    batch = run_import(start_import("entries", csv, user: user, options: { "decimal" => "," }), user: user)

    expect(Accounting::JournalEntry.find_by(import_batch_id: batch.id).lines.first.debit).to eq(BigDecimal("1234.50"))
  end

  it "refuses a piece dated in a locked period, with the message of the lock (F01)" do
    Accounting::PeriodLock.create!(starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date.end_of_month, kind: :accounting, lock_reason: "VAT filed", locked_by: user, locked_at: Time.current)
    batch = run_import(start_import("entries", entries_csv([ balanced("A1", fiscal_year.start_date.iso8601), balanced("A2", (fiscal_year.start_date + 40).iso8601) ]), user: user), user: user)

    expect(batch.summary).to include("created" => 1, "refused" => 1)
    expect(batch.errors_list.first["message"]).to match(/locked/i)
  end

  it "refuses a piece outside any open fiscal year, and one with a single line" do
    csv = entries_csv([ balanced("A1", (fiscal_year.end_date + 5).iso8601), [ "A2", day, [ [ "604000", "5", "" ] ] ] ])
    batch = run_import(start_import("entries", csv, user: user), user: user)

    expect(batch.errors_list.map { |e| e["message"] }).to contain_exactly(/no open fiscal year/i, /at least two lines/i)
  end

  it "never creates an unknown partner unless it is confirmed" do
    csv = "piece;date;journal;account;debit;credit;partner\nA1;#{day};OD;400000;10;;Newcomer Ltd\nA1;#{day};OD;700000;;10;\n"
    batch = run_import(start_import("entries", csv, user: user), user: user)
    expect(batch.errors_list.first["message"]).to include("partner Newcomer Ltd is unknown")
    expect(Accounting::Partner.where(name: "Newcomer Ltd")).to be_empty

    batch = start_import("entries", csv, user: user)
    batch.update!(mapping: batch.mapping.merge("resolutions" => { "partners" => { "Newcomer Ltd" => "create" } }))
    run_import(batch, user: user)
    expect(Accounting::Partner.find_by(name: "Newcomer Ltd")).to have_attributes(import_batch_id: batch.id)
    expect(Accounting::JournalEntry.find_by(external_id: "A1").lines.find_by(account: account_400).partner.name).to eq("Newcomer Ltd")
  end

  it "reverses a validated piece instead of deleting it, with the reason, when a batch is taken back" do
    batch = run_import(start_import("entries", entries_csv([ balanced("A1", day), balanced("A2", day) ]), user: user), user: user)
    posted = Accounting::JournalEntry.find_by(external_id: "A1")
    Accounting::PostJournalEntry.call!(entry: posted)

    expect { Imports::Undo.call(batch: batch, user: user) }.to raise_error(Imports::Undo::Refused, /reason/i)
    expect { Imports::Undo.call(batch: batch, user: user, reason: "Wrong file") }.to change(Accounting::JournalEntry, :count).by(-1 + 1)

    expect(posted.reload).to be_reversed
    expect(Accounting::JournalEntry.exists?(external_id: "A2")).to be(false)
    expect(batch.reload).to have_attributes(result: "undone", undo_reason: "Wrong file", undone_by: user)
  end

  it "reads an XLSX file the same way, and traces the import in the audit trail" do
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Entries") do |sheet|
      sheet.add_row(%w[piece date journal account debit credit])
      sheet.add_row([ "X1", Date.parse(day), "OD", "604000", 12.5, nil ])
      sheet.add_row([ "X1", Date.parse(day), "OD", "440000", nil, 12.5 ])
    end
    batch = run_import(start_import("entries", package.to_stream.read, user: user, filename: "pieces.xlsx"), user: user)

    expect(Accounting::JournalEntry.find_by(external_id: "X1").lines.sum(:debit)).to eq(BigDecimal("12.5"))
    log = Accounting::AuditLog.where(action: "guided_import").last
    expect(log).to have_attributes(user_id: user.id)
    expect(log.payload).to include("kind" => "entries", "filename" => "pieces.xlsx", "batch_id" => batch.id, "created" => 1)
    expect(log.payload["sha256"]).to eq(batch.file_sha256)
  end
end
