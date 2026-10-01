require "csv"

# Bank statement as a CSV file, for the banks that give no CAMT/MT940 (typically abroad). First row = header with
# `date` and either `amount` (signed) or `debit`/`credit`; optional `value_date`, `reference`, `description`,
# `currency` (must equal the account's). Delimiter `,` or `;`, dates ISO or dd/mm/yyyy, decimal point or comma.
# Rows without a reference get a fingerprint, so importing the same file twice creates nothing. All or nothing.
class Accounting::ImportCsvStatement
  def self.call(csv:, bank_account:)
    rows = parse(csv.to_s.delete_prefix("﻿"), bank_account)
    imported = 0

    ApplicationRecord.transaction do
      rows.each do |row|
        next if Accounting::BankTransaction.exists?(bank_account: bank_account, reference: row[:reference])

        Accounting::BankTransaction.create!(bank_account: bank_account, currency: bank_account.currency,
                                            raw_data: { csv: true }, **row)
        imported += 1
      end
    end
    LightService::Context.make(imported_count: imported)
  rescue StandardError => e
    LightService::Context.make(imported_count: 0).tap { |ctx| ctx.fail!("Import error: #{e.message}") }
  end

  def self.parse(csv, bank_account)
    delimiter = csv.lines.first.to_s.count(";") > csv.lines.first.to_s.count(",") ? ";" : ","
    table = CSV.parse(csv, headers: true, col_sep: delimiter, header_converters: ->(h) { h.to_s.strip.downcase })
    headers = table.headers
    raise "missing column: date" unless headers.include?("date")
    raise "missing column: amount (or debit/credit)" unless headers.include?("amount") || headers.include?("debit") || headers.include?("credit")

    table.each_with_index.map { |row, index| build(row, index + 2, bank_account) }
  end
  private_class_method :parse

  def self.build(row, line, bank_account)
    currency = row["currency"].to_s.strip.upcase
    raise "currency #{currency} does not match the account currency #{bank_account.currency}" if currency.present? && currency != bank_account.currency

    date   = parse_date(row["date"])
    amount = row["amount"].present? ? decimal(row["amount"]) : decimal(row["credit"]) - decimal(row["debit"])
    raise "no amount" if amount.zero?

    description = row["description"].to_s.strip.presence
    reference   = row["reference"].to_s.strip.presence || fingerprint(date, amount, description)
    { transaction_date: date, value_date: (parse_date(row["value_date"]) if row["value_date"].present?),
      amount: amount, description: description, reference: reference }
  rescue ArgumentError, Date::Error => e
    raise "line #{line}: #{e.message}"
  rescue RuntimeError => e
    raise e.message.start_with?("line") ? e.message : "line #{line}: #{e.message}"
  end
  private_class_method :build

  def self.parse_date(value)
    text = value.to_s.strip
    text.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z}) ? Date.strptime(text, "%d/%m/%Y") : Date.iso8601(text)
  end
  private_class_method :parse_date

  # "1.250,50" and "1,250.50" and "-1250.5": the last separator is the decimal one.
  def self.decimal(value)
    text = value.to_s.strip.delete(" ")
    return BigDecimal("0") if text.empty?

    text = if text.rindex(",").to_i > text.rindex(".").to_i then text.delete(".").tr(",", ".") else text.delete(",") end
    BigDecimal(text)
  end
  private_class_method :decimal

  def self.fingerprint(date, amount, description)
    "csv-#{Digest::SHA256.hexdigest([ date, amount.to_s("F"), description ].join('|'))[0, 16]}"
  end
  private_class_method :fingerprint
end
