# F13a: a file of entries in the shape the guided import reads, and the run of it from the upload on.
module ImportHelpers
  ENTRY_HEADER = "piece;date;journal;account;debit;credit;label".freeze

  # pieces: [[key, date, [[account, debit, credit], ...]], ...]
  def entries_csv(pieces, journal: "OD")
    lines = pieces.flat_map do |key, date, rows|
      rows.map { |account, debit, credit| [ key, date, journal, account, debit, credit, "Line #{key}" ].join(";") }
    end
    ([ ENTRY_HEADER ] + lines).join("\n") + "\n"
  end

  def balanced(key, date, amount = "10.00") = [ key, date, [ [ "604000", amount, "" ], [ "440000", "", amount ] ] ]

  def start_import(kind, data, user:, filename: "file.csv", **options)
    Imports::Start.call(user: user, kind: kind, filename: filename, data: data, **options)
  end

  def run_import(batch, user:, dry_run: false) = Imports::Run.call(batch: batch, user: user, dry_run: dry_run)
end

RSpec.configure { |config| config.include ImportHelpers }
