require "csv"

# F13b: the standard data exports (chart of accounts, partners, journals, entries with their lines) as CSV, JSON and XLSX. Rows are read in
# batches by key and written as they go, so that a large ledger is never held in memory (XLSX is built whole: past XLSX_MAX_ROWS the CSV is
# asked for). Every row carries `schema_version`; the columns are listed in docs/exports.md (Exports::Dictionary). Amounts are text, as the
# database holds them: no float on the way. A change of column is a new schema version.
class Exports::Standard
  SCHEMA_VERSION = 1
  BATCH = 1_000
  XLSX_MAX_ROWS = 100_000
  class TooLarge < StandardError; end

  ENTRY_LINES = "accounting_journal_entry_lines"
  ENTRIES     = "accounting_journal_entries"

  DATASETS = {
    "entries" => {
      relation: -> {
        Accounting::JournalEntryLine.joins(:journal_entry, :account)
          .joins("JOIN accounting_journals j ON j.id = #{ENTRIES}.journal_id", "JOIN accounting_fiscal_years fy ON fy.id = #{ENTRIES}.fiscal_year_id")
          .joins("LEFT JOIN accounting_partners p ON p.id = #{ENTRY_LINES}.partner_id")
      },
      key: "#{ENTRY_LINES}.id",
      columns: { "entry_id" => "#{ENTRIES}.id", "reference" => "#{ENTRIES}.reference", "entry_date" => "#{ENTRIES}.entry_date", "journal" => "j.code",
                 "status" => "#{ENTRIES}.status", "fiscal_year" => "fy.year", "description" => "#{ENTRIES}.description", "external_id" => "#{ENTRIES}.external_id",
                 "line_id" => "#{ENTRY_LINES}.id", "account" => "accounting_accounts.code", "partner" => "p.name", "partner_vat" => "p.vat_number",
                 "label" => "#{ENTRY_LINES}.label", "debit" => "#{ENTRY_LINES}.debit::text", "credit" => "#{ENTRY_LINES}.credit::text",
                 "currency" => "COALESCE(#{ENTRY_LINES}.currency, 'EUR')", "amount_currency" => "#{ENTRY_LINES}.amount_currency::text",
                 "exchange_rate" => "#{ENTRY_LINES}.exchange_rate::text" },
      enums: { "status" => -> { Accounting::JournalEntry.statuses } },
      period: "#{ENTRIES}.entry_date"
    },
    "accounts" => {
      relation: -> { Accounting::Account.joins("LEFT JOIN accounting_accounts pa ON pa.id = accounting_accounts.parent_id") },
      key: "accounting_accounts.id",
      columns: { "code" => "accounting_accounts.code", "label_fr" => "accounting_accounts.label_fr", "label_nl" => "accounting_accounts.label_nl",
                 "account_type" => "accounting_accounts.account_type", "normal_balance" => "accounting_accounts.normal_balance",
                 "account_class" => "accounting_accounts.account_class", "parent_code" => "pa.code", "reconcilable" => "accounting_accounts.reconcilable",
                 "active" => "accounting_accounts.active", "currency" => "accounting_accounts.currency" },
      enums: { "account_type" => -> { Accounting::Account.account_types }, "normal_balance" => -> { Accounting::Account.normal_balances } }
    },
    "partners" => {
      relation: -> { Accounting::Partner.all },
      key: "accounting_partners.id",
      columns: %w[id name partner_type vat_number email phone street zip city country iban bic payment_terms_days external_ref language currency active]
                 .index_with { |c| "accounting_partners.#{c}" },
      enums: { "partner_type" => -> { Accounting::Partner.partner_types } }
    },
    "journals" => {
      relation: -> { Accounting::Journal.all },
      key: "accounting_journals.id",
      columns: %w[code label_fr journal_type sequence_prefix active].index_with { |c| "accounting_journals.#{c}" },
      enums: { "journal_type" => -> { Accounting::Journal.journal_types } }
    },
    "vat_codes" => {
      relation: -> { Accounting::VatCode.all },
      key: "accounting_vat_codes.id",
      columns: %w[code label sens nature rate].index_with { |c| "accounting_vat_codes.#{c}" },
      enums: { "sens" => -> { Accounting::VatCode.sens }, "nature" => -> { Accounting::VatCode.natures } }
    }
  }.freeze

  attr_reader :dataset

  def initialize(dataset, from: nil, to: nil)
    @dataset = dataset.to_s
    @spec = DATASETS[@dataset] or raise ArgumentError, "Unknown dataset #{dataset}"
    raise ArgumentError, "The period ends before it starts" if from && to && to < from

    @from, @to, @tenant = from, to, ActsAsTenant.current_tenant
  end

  def headers = @spec[:columns].keys

  def csv
    Enumerator.new do |out|
      out << CSV.generate_line([ "schema_version", *headers ])
      each_batch { |rows| out << rows.map { |row| CSV.generate_line([ SCHEMA_VERSION, *row.map { |v| plain(v) } ]) }.join }
    end
  end

  def json
    Enumerator.new do |out|
      out << %({"schema_version":#{SCHEMA_VERSION},"dataset":#{@dataset.to_json},"generated_at":#{Time.current.utc.iso8601.to_json},"rows":[)
      first = true
      each_batch do |rows|
        out << rows.map { |row| (first ? "" : ",").tap { first = false } + JSON.generate(headers.zip(row.map { |v| json_value(v) }).to_h) }.join
      end
      out << "]}"
    end
  end

  def xlsx
    raise TooLarge, "More than #{XLSX_MAX_ROWS} rows: use the CSV export" if with_tenant { scoped.count } > XLSX_MAX_ROWS

    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: @dataset.first(31)) do |sheet|
      sheet.add_row([ "schema_version", *headers ])
      each_batch { |rows| rows.each { |row| sheet.add_row([ SCHEMA_VERSION.to_s, *row.map { |v| plain(v) } ], types: :string) } }
    end
    package.to_stream.read
  end

  private

  def with_tenant(&) = ActsAsTenant.with_tenant(@tenant, &)

  def scoped
    relation = @spec[:relation].call
    relation = relation.where("#{@spec[:period]} >= ?", @from) if @from && @spec[:period]
    relation = relation.where("#{@spec[:period]} <= ?", @to) if @to && @spec[:period]
    relation
  end

  def each_batch
    with_tenant do
      decoders = (@spec[:enums] || {}).to_h { |column, values| [ headers.index(column), values.call.invert ] }
      last = 0
      loop do
        rows = scoped.where("#{@spec[:key]} > ?", last).order(Arel.sql(@spec[:key])).limit(BATCH)
                     .pluck(Arel.sql(@spec[:key]), *@spec[:columns].values.each_with_index.map { |sql, i| Arel.sql("#{sql} AS x#{i}") }) # aliased: pluck must not cast a column by its name
        break if rows.empty?

        last = rows.last.first
        yield rows.map { |row| row.drop(1).each_with_index.map { |v, i| decoders.key?(i) ? decoders[i].fetch(v, v) : v } }
      end
    end
  end

  def plain(value) = value.respond_to?(:iso8601) ? value.iso8601 : value
  def json_value(value) = value.respond_to?(:iso8601) ? value.iso8601 : value
end
