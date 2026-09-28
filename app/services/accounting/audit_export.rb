require "csv"

# R20 full audit export (docs/dev/reports/spec.md §13): entries with all their lines, chart of accounts,
# partners, journals and VAT codes, as flat CSV and JSON files in a ZIP. SAF-T is not produced (only on
# explicit request, per the spec).
class Accounting::AuditExport
  DATASETS = {
    "entries" => {
      headers: %w[entry_id reference entry_date journal status fiscal_year line_id account partner label debit credit vat_code],
      relation: -> { Accounting::JournalEntryLine.joins(:journal_entry, :account).joins("JOIN accounting_journals j ON j.id = accounting_journal_entries.journal_id").joins("LEFT JOIN accounting_partners p ON p.id = accounting_journal_entry_lines.partner_id") },
      columns: [ "accounting_journal_entries.id", "accounting_journal_entries.reference", "accounting_journal_entries.entry_date", "j.code",
                 "accounting_journal_entries.status", "accounting_journal_entries.fiscal_year_id", "accounting_journal_entry_lines.id", "accounting_accounts.code",
                 "p.name", "accounting_journal_entry_lines.label", "accounting_journal_entry_lines.debit", "accounting_journal_entry_lines.credit",
                 "accounting_journal_entry_lines.vat_code" ],
      order: "accounting_journal_entries.entry_date, accounting_journal_entries.id, accounting_journal_entry_lines.id"
    },
    "accounts" => { headers: %w[code label_fr label_nl account_type normal_balance account_class reconcilable active], relation: -> { Accounting::Account.all },
                    columns: %w[code label_fr label_nl account_type normal_balance account_class reconcilable active], order: "code" },
    "partners" => { headers: %w[id name partner_type vat_number country iban active], relation: -> { Accounting::Partner.all },
                    columns: %w[id name partner_type vat_number country iban active], order: "id" },
    "journals" => { headers: %w[code label_fr journal_type sequence_prefix active], relation: -> { Accounting::Journal.all },
                    columns: %w[code label_fr journal_type sequence_prefix active], order: "code" },
    "vat_codes" => { headers: %w[code label sens nature rate], relation: -> { Accounting::VatCode.all },
                     columns: %w[code label sens nature rate], order: "code" }
  }.freeze

  # Enum columns come back from SQL as integers; the export writes their names.
  ENUMS = {
    "entries" => { "status" => -> { Accounting::JournalEntry.statuses } },
    "accounts" => { "account_type" => -> { Accounting::Account.account_types }, "normal_balance" => -> { Accounting::Account.normal_balances } },
    "partners" => { "partner_type" => -> { Accounting::Partner.partner_types } },
    "journals" => { "journal_type" => -> { Accounting::Journal.journal_types } },
    "vat_codes" => { "sens" => -> { Accounting::VatCode.sens }, "nature" => -> { Accounting::VatCode.natures } }
  }.freeze

  def self.call(fiscal_year:) = new(fiscal_year).call

  def initialize(fiscal_year)
    @fiscal_year = fiscal_year
  end

  # => ZIP data (String)
  def call
    Accounting::Zipper.build(files)
  end

  def files
    DATASETS.flat_map do |name, spec|
      rows = decode(name, spec[:headers], rows_for(name, spec))
      [ [ "#{name}.csv", csv(spec[:headers], rows) ], [ "#{name}.json", JSON.pretty_generate(rows.map { |r| spec[:headers].zip(r.map { |v| json_value(v) }).to_h }) ] ]
    end
  end

  private

  def rows_for(name, spec)
    relation = spec[:relation].call
    relation = relation.where(accounting_journal_entries: { fiscal_year_id: @fiscal_year.id }) if name == "entries"
    relation.order(Arel.sql(spec[:order])).pluck(*spec[:columns].map { |c| Arel.sql(c.include?(".") ? c : "#{relation.klass.table_name}.#{c}") })
  end

  def decode(name, headers, rows)
    maps = ENUMS.fetch(name, {}).to_h { |column, values| [ headers.index(column), values.call.invert ] }
    rows.map { |row| row.each_with_index.map { |value, i| maps.key?(i) ? maps[i].fetch(value, value) : value } }
  end

  def csv(headers, rows)
    CSV.generate { |out| out << headers; rows.each { |r| out << r.map { |v| csv_value(v) } } }
  end

  def csv_value(value) = value.is_a?(BigDecimal) ? value.to_s("F") : value
  def json_value(value) = value.is_a?(BigDecimal) ? value.to_s("F") : value
end
