require "csv"

# Renders a Reports::Result as CSV (docs/dev/reports/spec.md §14): UTF-8 with
# a BOM, `;` separator and comma decimal in fr/nl, `,` separator and dot
# decimal in en, one header row, never a totals row mixed into the data.
class Reports::Exporters::Csv
  SEPARATORS = { fr: [ ";", "," ], nl: [ ";", "," ], en: [ ",", "." ] }.freeze

  def self.call(result, columns:, locale: I18n.locale)
    new(result, columns: columns, locale: locale).call
  end

  def initialize(result, columns:, locale:)
    @result = result
    @columns = columns
    @col_sep, @decimal_sep = SEPARATORS.fetch(locale.to_sym, SEPARATORS[:en])
  end

  def call
    body = ::CSV.generate(col_sep: col_sep) do |csv|
      csv << columns.map(&:first)
      result.rows.each { |row| csv << columns.map { |_, extractor| format_value(extract(row, extractor)) } }
    end
    "﻿#{body}"
  end

  private

  attr_reader :result, :columns, :col_sep, :decimal_sep

  def extract(row, extractor)
    extractor.respond_to?(:call) ? extractor.call(row) : row.public_send(extractor)
  end

  def format_value(value)
    return value unless value.is_a?(BigDecimal) || value.is_a?(Float)

    s = format("%.2f", value)
    decimal_sep == "," ? s.tr(".", ",") : s
  end
end
